use std::collections::HashMap;
use std::io;
use std::net::{SocketAddr, ToSocketAddrs, UdpSocket};
use std::os::fd::{AsRawFd, FromRawFd, OwnedFd, RawFd};
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{Arc, Condvar, Mutex, MutexGuard};
use std::thread::{self, JoinHandle};
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use base64::engine::general_purpose::STANDARD;
use base64::Engine;
use boringtun::noise::{Tunn, TunnResult};
use boringtun::x25519::{PublicKey, StaticSecret};
use napi_derive_ohos::napi;
use napi_ohos::bindgen_prelude::*;
use once_cell::sync::Lazy;

const DEFAULT_MTU: usize = 1280;
const MAX_MTU: usize = 1500;
const HANDSHAKE_INDEX: u32 = 1;
const WG_MESSAGE_HANDSHAKE_INITIATION: u32 = 1;
const WG_MESSAGE_DATA: u32 = 4;
const REKEY_TIMEOUT_MS: u64 = 5_000;
const KEEPALIVE_TIMEOUT_MS: u64 = 10_000;
const DATA_SILENCE_REKEY_MS: u64 = 15_000;
const MIN_TIMER_DELAY_MS: u64 = 500;

static NEXT_HANDLE: AtomicU64 = AtomicU64::new(1);
static GLOBAL_TICK_COUNT: AtomicU64 = AtomicU64::new(0);
static REGISTRY: Lazy<Mutex<HashMap<u64, Arc<TunnelRuntime>>>> =
    Lazy::new(|| Mutex::new(HashMap::new()));

#[napi(object)]
pub struct NativeTunnelStats {
    pub running: bool,
    pub tx_bytes: f64,
    pub rx_bytes: f64,
    pub latest_handshake_seconds: f64,
    pub latest_packet_sent_seconds: f64,
    pub loss: f64,
    pub rtt_millis: f64,
}

struct TunnelRuntime {
    socket: UdpSocket,
    peer_addr: SocketAddr,
    tunn: Mutex<Tunn>,
    mtu: usize,
    persistent_keepalive_ms: u64,
    running: AtomicBool,
    last_network_send_ms: AtomicU64,
    tick_count: AtomicU64,
    timer_state: Mutex<TimerState>,
    timer_condvar: Condvar,
    workers: Mutex<Vec<JoinHandle<()>>>,
    stop_writers: Mutex<Vec<OwnedFd>>,
}

struct TimerState {
    deadlines_ms: Vec<u64>,
}

#[napi]
pub fn create_tunnel(
    private_key: String,
    peer_public_key: String,
    preshared_key: String,
    endpoint_host: String,
    endpoint_port: u32,
    persistent_keepalive: u32,
    mtu: u32,
) -> Result<i32> {
    let private_key = StaticSecret::from(decode_key(&private_key, "privateKey")?);
    let peer_public_key = PublicKey::from(decode_key(&peer_public_key, "peerPublicKey")?);
    let preshared_key = if preshared_key.trim().is_empty() {
        None
    } else {
        Some(decode_key(&preshared_key, "presharedKey")?)
    };
    let endpoint_port = to_u16(endpoint_port, "endpointPort")?;
    let persistent_keepalive_ms = u64::from(persistent_keepalive) * 1_000;
    let keepalive = if persistent_keepalive == 0 {
        None
    } else {
        Some(to_u16(persistent_keepalive, "persistentKeepalive")?)
    };
    let mtu = clamp_mtu(mtu);
    let peer_addr = resolve_endpoint(&endpoint_host, endpoint_port)?;
    let socket = bind_udp(peer_addr)?;

    let tunn = Tunn::new(
        private_key,
        peer_public_key,
        preshared_key,
        keepalive,
        HANDSHAKE_INDEX,
        None,
    );

    let handle = NEXT_HANDLE.fetch_add(1, Ordering::Relaxed);
    if handle > i32::MAX as u64 {
        return Err(error("tunnel handle space exhausted"));
    }
    let runtime = Arc::new(TunnelRuntime {
        socket,
        peer_addr,
        tunn: Mutex::new(tunn),
        mtu,
        persistent_keepalive_ms,
        running: AtomicBool::new(false),
        last_network_send_ms: AtomicU64::new(0),
        tick_count: AtomicU64::new(0),
        timer_state: Mutex::new(TimerState {
            deadlines_ms: Vec::new(),
        }),
        timer_condvar: Condvar::new(),
        workers: Mutex::new(Vec::new()),
        stop_writers: Mutex::new(Vec::new()),
    });

    registry()?.insert(handle, runtime);
    Ok(handle as i32)
}

#[napi]
pub fn get_tunnel_socket_fd(handle: i32) -> Result<i32> {
    let runtime = get_runtime(handle)?;
    Ok(runtime.socket.as_raw_fd())
}

#[napi]
pub fn start_tunnel(handle: i32, tun_fd: i32) -> Result<()> {
    let runtime = get_runtime(handle)?;
    runtime.start(tun_fd)
}

#[napi]
pub fn stop_tunnel(handle: i32) -> Result<()> {
    let runtime = registry()?.remove(&handle_key(handle)?);
    if let Some(runtime) = runtime {
        runtime.stop();
    }
    Ok(())
}

#[napi]
pub fn get_tunnel_stats(handle: i32) -> Result<NativeTunnelStats> {
    let runtime = get_runtime(handle)?;
    let tunn = runtime.lock_tunn()?;
    let (handshake, tx, rx, loss, rtt) = tunn.stats();

    Ok(NativeTunnelStats {
        running: runtime.running.load(Ordering::SeqCst),
        tx_bytes: tx as f64,
        rx_bytes: rx as f64,
        latest_handshake_seconds: handshake.map(|value| value.as_secs_f64()).unwrap_or(-1.0),
        latest_packet_sent_seconds: elapsed_seconds_since(
            runtime.last_network_send_ms.load(Ordering::SeqCst),
        ),
        loss: loss as f64,
        rtt_millis: rtt.map(|value| value as f64).unwrap_or(-1.0),
    })
}

#[napi]
pub fn get_tick_count() -> Result<f64> {
    Ok(GLOBAL_TICK_COUNT.load(Ordering::SeqCst) as f64)
}

#[napi]
pub fn get_tunnel_tick_count(handle: i32) -> Result<f64> {
    let runtime = get_runtime(handle)?;
    Ok(runtime.tick_count.load(Ordering::SeqCst) as f64)
}

#[napi]
pub fn get_persistent_keepalive_seconds(handle: i32) -> Result<f64> {
    let runtime = get_runtime(handle)?;
    Ok((runtime.persistent_keepalive_ms / 1_000) as f64)
}

#[napi]
pub fn force_tunnel_handshake(handle: i32) -> Result<()> {
    let runtime = get_runtime(handle)?;
    runtime.force_handshake()
}

impl TunnelRuntime {
    fn start(self: Arc<Self>, tun_fd: RawFd) -> Result<()> {
        if tun_fd < 0 {
            return Err(error("invalid TUN fd"));
        }
        if self.running.swap(true, Ordering::SeqCst) {
            close_if_valid(tun_fd);
            return Ok(());
        }

        if let Err(err) = set_nonblocking(tun_fd, true) {
            self.running.store(false, Ordering::SeqCst);
            close_if_valid(tun_fd);
            return Err(err);
        }
        let tun_for_read = unsafe { libc::dup(tun_fd) };
        let tun_for_write = unsafe { libc::dup(tun_fd) };
        if tun_for_read < 0 || tun_for_write < 0 {
            self.running.store(false, Ordering::SeqCst);
            close_if_valid(tun_for_read);
            close_if_valid(tun_for_write);
            return Err(to_error(io::Error::last_os_error()));
        }
        close_if_valid(tun_fd);
        let tun_for_read = unsafe { OwnedFd::from_raw_fd(tun_for_read) };
        let tun_for_write = unsafe { OwnedFd::from_raw_fd(tun_for_write) };

        if let Err(err) = set_nonblocking(tun_for_read.as_raw_fd(), true) {
            self.running.store(false, Ordering::SeqCst);
            return Err(err);
        }
        if let Err(err) = set_nonblocking(tun_for_write.as_raw_fd(), true) {
            self.running.store(false, Ordering::SeqCst);
            return Err(err);
        }

        let socket_for_read = match self.socket.try_clone().map_err(to_error) {
            Ok(socket) => socket,
            Err(err) => {
                self.running.store(false, Ordering::SeqCst);
                return Err(err);
            }
        };
        let socket_for_write = match self.socket.try_clone().map_err(to_error) {
            Ok(socket) => socket,
            Err(err) => {
                self.running.store(false, Ordering::SeqCst);
                return Err(err);
            }
        };
        let timer_socket = match self.socket.try_clone().map_err(to_error) {
            Ok(socket) => socket,
            Err(err) => {
                self.running.store(false, Ordering::SeqCst);
                return Err(err);
            }
        };
        let (tun_stop_read, tun_stop_write) = match create_pipe() {
            Ok(pipe) => pipe,
            Err(err) => {
                self.running.store(false, Ordering::SeqCst);
                return Err(err);
            }
        };
        let (udp_stop_read, udp_stop_write) = match create_pipe() {
            Ok(pipe) => pipe,
            Err(err) => {
                self.running.store(false, Ordering::SeqCst);
                return Err(err);
            }
        };

        let tun_read_runtime = self.clone();
        let tun_worker = match thread::Builder::new()
            .name("wg-tun-reader".to_string())
            .spawn(move || {
                tun_read_runtime.tun_reader_loop(tun_for_read, tun_stop_read, socket_for_write);
            })
            .map_err(to_error) {
            Ok(worker) => worker,
            Err(err) => {
                self.running.store(false, Ordering::SeqCst);
                return Err(err);
            }
        };

        let udp_runtime = self.clone();
        let udp_worker = match thread::Builder::new()
            .name("wg-udp-reader".to_string())
            .spawn(move || {
                udp_runtime.udp_reader_loop(socket_for_read, udp_stop_read, tun_for_write);
            })
            .map_err(to_error) {
            Ok(worker) => worker,
            Err(err) => {
                self.running.store(false, Ordering::SeqCst);
                let _ = write_stop_signal(tun_stop_write.as_raw_fd());
                let _ = tun_worker.join();
                return Err(err);
            }
        };

        let timer_runtime = self.clone();
        let timer_worker = match thread::Builder::new()
            .name("wg-timer".to_string())
            .spawn(move || {
                timer_runtime.timer_loop(timer_socket);
            })
            .map_err(to_error) {
            Ok(worker) => worker,
            Err(err) => {
                self.running.store(false, Ordering::SeqCst);
                self.timer_condvar.notify_all();
                let _ = write_stop_signal(tun_stop_write.as_raw_fd());
                let _ = write_stop_signal(udp_stop_write.as_raw_fd());
                let _ = tun_worker.join();
                let _ = udp_worker.join();
                return Err(err);
            }
        };

        let mut workers = match self.lock_workers() {
            Ok(workers) => workers,
            Err(err) => {
                self.running.store(false, Ordering::SeqCst);
                self.timer_condvar.notify_all();
                let _ = write_stop_signal(tun_stop_write.as_raw_fd());
                let _ = write_stop_signal(udp_stop_write.as_raw_fd());
                let _ = tun_worker.join();
                let _ = udp_worker.join();
                let _ = timer_worker.join();
                return Err(err);
            }
        };
        let mut stop_writers = match self.lock_stop_writers() {
            Ok(stop_writers) => stop_writers,
            Err(err) => {
                self.running.store(false, Ordering::SeqCst);
                self.timer_condvar.notify_all();
                let _ = write_stop_signal(tun_stop_write.as_raw_fd());
                let _ = write_stop_signal(udp_stop_write.as_raw_fd());
                let _ = tun_worker.join();
                let _ = udp_worker.join();
                let _ = timer_worker.join();
                return Err(err);
            }
        };
        stop_writers.push(tun_stop_write);
        stop_writers.push(udp_stop_write);
        workers.push(tun_worker);
        workers.push(udp_worker);
        workers.push(timer_worker);
        drop(stop_writers);
        drop(workers);
        self.schedule_persistent_keepalive();
        self.send_initial_handshake();
        Ok(())
    }

    fn stop(&self) {
        self.running.store(false, Ordering::SeqCst);
        self.timer_condvar.notify_all();
        if let Ok(stop_writers) = self.stop_writers.lock() {
            for writer in stop_writers.iter() {
                let _ = write_stop_signal(writer.as_raw_fd());
            }
        }
        if let Ok(mut workers) = self.workers.lock() {
            while let Some(worker) = workers.pop() {
                let _ = worker.join();
            }
        }
        if let Ok(mut stop_writers) = self.stop_writers.lock() {
            stop_writers.clear();
        }
    }

    fn tun_reader_loop(&self, tun_fd: OwnedFd, stop_fd: OwnedFd, socket: UdpSocket) {
        let mut packet = vec![0u8; self.mtu + 256];
        let mut out = vec![0u8; self.mtu + 512];

        while self.running.load(Ordering::SeqCst) {
            match poll_readable_or_stop(tun_fd.as_raw_fd(), stop_fd.as_raw_fd()) {
                Ok(PollOutcome::Ready) => {}
                Ok(PollOutcome::Stopped) => break,
                Err(err) if is_retry(&err) => continue,
                Err(_) => break,
            }
            self.bump_tick();

            match read_fd(tun_fd.as_raw_fd(), &mut packet) {
                Ok(0) => continue,
                Ok(size) => {
                    if should_drop_quiet_tun_packet(&packet[..size]) {
                        continue;
                    }
                    if let Ok(mut tunn) = self.lock_tunn() {
                        let result = tunn.encapsulate(&packet[..size], &mut out);
                        self.handle_tunn_result(result, &socket, None);
                    }
                }
                Err(err) if is_retry(&err) => continue,
                Err(_) => break,
            }
        }
    }

    fn udp_reader_loop(&self, socket: UdpSocket, stop_fd: OwnedFd, tun_fd: OwnedFd) {
        let mut datagram = vec![0u8; self.mtu + 512];
        let mut out = vec![0u8; self.mtu + 512];

        while self.running.load(Ordering::SeqCst) {
            match poll_readable_or_stop(socket.as_raw_fd(), stop_fd.as_raw_fd()) {
                Ok(PollOutcome::Ready) => {}
                Ok(PollOutcome::Stopped) => break,
                Err(err) if is_retry(&err) => continue,
                Err(_) => break,
            }
            self.bump_tick();

            match socket.recv_from(&mut datagram) {
                Ok((size, src)) => {
                    if src != self.peer_addr {
                        continue;
                    }

                    let received_message_type = wireguard_message_type(&datagram[..size]);
                    if let Ok(mut tunn) = self.lock_tunn() {
                        let result = tunn.decapsulate(Some(src.ip()), &datagram[..size], &mut out);
                        self.handle_tunn_result(result, &socket, Some(tun_fd.as_raw_fd()));

                        loop {
                            let result = tunn.decapsulate(Some(src.ip()), &[], &mut out);
                            if !should_flush_again(&result) {
                                let _ = self.handle_tunn_result(
                                    result,
                                    &socket,
                                    Some(tun_fd.as_raw_fd()),
                                );
                                break;
                            }
                            let _ = self.handle_tunn_result(
                                result,
                                &socket,
                                Some(tun_fd.as_raw_fd()),
                            );
                        }
                    }
                    if received_message_type == Some(WG_MESSAGE_DATA) {
                        self.schedule_timer_after(Duration::from_millis(KEEPALIVE_TIMEOUT_MS));
                    }
                }
                Err(err) if is_retry(&err) => continue,
                Err(_) => break,
            }
        }
    }

    fn timer_loop(&self, socket: UdpSocket) {
        let mut out = vec![0u8; self.mtu + 512];

        while self.running.load(Ordering::SeqCst) {
            if !self.wait_for_timer() {
                continue;
            }
            self.bump_tick();
            if let Ok(mut tunn) = self.lock_tunn() {
                let result = tunn.update_timers(&mut out);
                if self.handle_tunn_result(result, &socket, None) {
                    self.schedule_persistent_keepalive();
                }
            }
        }
    }

    fn send_initial_handshake(&self) {
        let mut out = vec![0u8; self.mtu + 512];
        if let Ok(mut tunn) = self.lock_tunn() {
            let result = tunn.format_handshake_initiation(&mut out, false);
            let _ = self.handle_tunn_result(result, &self.socket, None);
        }
    }

    fn force_handshake(&self) -> Result<()> {
        let mut out = vec![0u8; self.mtu + 512];
        let result = {
            let mut tunn = self.lock_tunn()?;
            tunn.format_handshake_initiation(&mut out, true)
        };
        let _ = self.handle_tunn_result(result, &self.socket, None);
        Ok(())
    }

    fn handle_tunn_result(
        &self,
        result: TunnResult<'_>,
        socket: &UdpSocket,
        tun_fd: Option<RawFd>,
    ) -> bool {
        match result {
            TunnResult::Done => return true,
            TunnResult::Err(_) => {}
            TunnResult::WriteToNetwork(data) => {
                let timer_delay = self.timer_delay_for_network_write(data);
                if socket.send_to(data, self.peer_addr).is_ok() {
                    self.last_network_send_ms
                        .store(now_millis(), Ordering::SeqCst);
                    if let Some(delay) = timer_delay {
                        self.schedule_timer_after(delay);
                    }
                    self.schedule_persistent_keepalive();
                }
            }
            TunnResult::WriteToTunnelV4(data, _) | TunnResult::WriteToTunnelV6(data, _) => {
                if let Some(fd) = tun_fd {
                    let _ = write_all_fd(fd, data);
                }
            }
        }
        false
    }

    fn timer_delay_for_network_write(&self, data: &[u8]) -> Option<Duration> {
        let message_type = wireguard_message_type(data)?;
        match message_type {
            WG_MESSAGE_HANDSHAKE_INITIATION => Some(Duration::from_millis(REKEY_TIMEOUT_MS)),
            WG_MESSAGE_DATA => Some(Duration::from_millis(DATA_SILENCE_REKEY_MS)),
            _ => None,
        }
    }

    fn schedule_persistent_keepalive(&self) {
        if self.persistent_keepalive_ms > 0 {
            self.schedule_timer_after(Duration::from_millis(self.persistent_keepalive_ms));
        }
    }

    fn schedule_timer_after(&self, duration: Duration) {
        let delay_ms = duration
            .as_millis()
            .min(u64::MAX as u128) as u64;
        let delay_ms = delay_ms.max(MIN_TIMER_DELAY_MS);
        let deadline = now_millis().saturating_add(delay_ms);
        if let Ok(mut state) = self.timer_state.lock() {
            let wake_earlier = state
                .deadlines_ms
                .iter()
                .copied()
                .min()
                .map_or(true, |current| deadline < current);
            state.deadlines_ms.push(deadline);
            prune_deadlines(&mut state.deadlines_ms, now_millis());
            if wake_earlier {
                self.timer_condvar.notify_one();
            }
        }
    }

    fn wait_for_timer(&self) -> bool {
        let mut state = match self.timer_state.lock() {
            Ok(state) => state,
            Err(_) => return false,
        };

        loop {
            if !self.running.load(Ordering::SeqCst) {
                return false;
            }

            let now = now_millis();
            prune_deadlines(&mut state.deadlines_ms, now);
            if let Some(deadline) = state.deadlines_ms.iter().copied().min() {
                if deadline <= now {
                    state.deadlines_ms.retain(|value| *value > now);
                    return true;
                }

                let until_deadline = deadline - now;
                let wait_result = self
                    .timer_condvar
                    .wait_timeout(state, Duration::from_millis(until_deadline));
                let (next_state, timeout_result) = match wait_result {
                    Ok(result) => result,
                    Err(_) => return false,
                };
                state = next_state;
                let _ = timeout_result;
                continue;
            }

            state = match self.timer_condvar.wait(state) {
                Ok(next_state) => next_state,
                Err(_) => return false,
            };
        }
    }

    fn bump_tick(&self) {
        self.tick_count.fetch_add(1, Ordering::SeqCst);
        GLOBAL_TICK_COUNT.fetch_add(1, Ordering::SeqCst);
    }

    fn lock_tunn(&self) -> Result<MutexGuard<'_, Tunn>> {
        self.tunn.lock().map_err(|_| error("WireGuard tunnel lock poisoned"))
    }

    fn lock_workers(&self) -> Result<MutexGuard<'_, Vec<JoinHandle<()>>>> {
        self.workers
            .lock()
            .map_err(|_| error("worker registry lock poisoned"))
    }

    fn lock_stop_writers(&self) -> Result<MutexGuard<'_, Vec<OwnedFd>>> {
        self.stop_writers
            .lock()
            .map_err(|_| error("stop pipe registry lock poisoned"))
    }
}

fn should_flush_again(result: &TunnResult<'_>) -> bool {
    matches!(result, TunnResult::WriteToNetwork(_))
}

fn now_millis() -> u64 {
    match SystemTime::now().duration_since(UNIX_EPOCH) {
        Ok(duration) => duration.as_millis().min(u64::MAX as u128) as u64,
        Err(_) => 0,
    }
}

fn elapsed_seconds_since(timestamp_ms: u64) -> f64 {
    if timestamp_ms == 0 {
        return -1.0;
    }

    let now = now_millis();
    if now < timestamp_ms {
        return 0.0;
    }
    (now - timestamp_ms) as f64 / 1000.0
}

fn prune_deadlines(deadlines: &mut Vec<u64>, now: u64) {
    deadlines.retain(|deadline| *deadline > now);
    deadlines.sort_unstable();
    deadlines.dedup();
    if deadlines.len() > 16 {
        deadlines.truncate(16);
    }
}

fn decode_key(value: &str, field_name: &str) -> Result<[u8; 32]> {
    let bytes = STANDARD
        .decode(value.trim())
        .map_err(|err| error(format!("{field_name} is not valid base64: {err}")))?;
    if bytes.len() != 32 {
        return Err(error(format!("{field_name} must decode to 32 bytes")));
    }

    let mut key = [0u8; 32];
    key.copy_from_slice(&bytes);
    Ok(key)
}

fn to_u16(value: u32, field_name: &str) -> Result<u16> {
    if value > u16::MAX as u32 {
        return Err(error(format!("{field_name} out of range")));
    }
    Ok(value as u16)
}

fn clamp_mtu(mtu: u32) -> usize {
    let mtu = if mtu == 0 { DEFAULT_MTU } else { mtu as usize };
    mtu.clamp(576, MAX_MTU)
}

fn resolve_endpoint(host: &str, port: u16) -> Result<SocketAddr> {
    let endpoint = if host.contains(':') && !host.starts_with('[') {
        format!("[{}]:{}", host, port)
    } else {
        format!("{}:{}", host, port)
    };
    endpoint
        .to_socket_addrs()
        .map_err(to_error)?
        .next()
        .ok_or_else(|| error("endpoint did not resolve"))
}

fn bind_udp(peer_addr: SocketAddr) -> Result<UdpSocket> {
    let bind_addr = match peer_addr {
        SocketAddr::V4(_) => "0.0.0.0:0",
        SocketAddr::V6(_) => "[::]:0",
    };
    UdpSocket::bind(bind_addr).map_err(to_error)
}

fn registry() -> Result<MutexGuard<'static, HashMap<u64, Arc<TunnelRuntime>>>> {
    REGISTRY
        .lock()
        .map_err(|_| error("tunnel registry lock poisoned"))
}

fn handle_key(handle: i32) -> Result<u64> {
    if handle <= 0 {
        return Err(error("invalid tunnel handle"));
    }
    Ok(handle as u64)
}

fn get_runtime(handle: i32) -> Result<Arc<TunnelRuntime>> {
    let key = handle_key(handle)?;
    registry()?
        .get(&key)
        .cloned()
        .ok_or_else(|| error("unknown tunnel handle"))
}

fn read_fd(fd: RawFd, buffer: &mut [u8]) -> io::Result<usize> {
    let result = unsafe { libc::read(fd, buffer.as_mut_ptr().cast(), buffer.len()) };
    if result < 0 {
        Err(io::Error::last_os_error())
    } else {
        Ok(result as usize)
    }
}

enum PollOutcome {
    Ready,
    Stopped,
}

fn poll_readable_or_stop(fd: RawFd, stop_fd: RawFd) -> io::Result<PollOutcome> {
    let mut poll_fds = [
        libc::pollfd {
            fd,
            events: libc::POLLIN,
            revents: 0,
        },
        libc::pollfd {
            fd: stop_fd,
            events: libc::POLLIN,
            revents: 0,
        },
    ];
    let result = unsafe { libc::poll(poll_fds.as_mut_ptr(), poll_fds.len() as libc::nfds_t, -1) };
    if result < 0 {
        return Err(io::Error::last_os_error());
    }
    if poll_fds[1].revents & (libc::POLLIN | libc::POLLERR | libc::POLLHUP | libc::POLLNVAL) != 0
    {
        return Ok(PollOutcome::Stopped);
    }
    if poll_fds[0].revents & libc::POLLIN != 0 {
        return Ok(PollOutcome::Ready);
    }
    if poll_fds[0].revents & (libc::POLLERR | libc::POLLHUP | libc::POLLNVAL) != 0 {
        return Err(io::Error::from_raw_os_error(libc::EIO));
    }
    Ok(PollOutcome::Stopped)
}

fn write_all_fd(fd: RawFd, mut data: &[u8]) -> io::Result<()> {
    while !data.is_empty() {
        let result = unsafe { libc::write(fd, data.as_ptr().cast(), data.len()) };
        if result < 0 {
            let err = io::Error::last_os_error();
            if is_retry(&err) {
                thread::sleep(Duration::from_millis(1));
                continue;
            }
            return Err(err);
        }
        data = &data[result as usize..];
    }
    Ok(())
}

fn set_nonblocking(fd: RawFd, nonblocking: bool) -> Result<()> {
    let flags = unsafe { libc::fcntl(fd, libc::F_GETFL, 0) };
    if flags < 0 {
        return Err(to_error(io::Error::last_os_error()));
    }

    let next = if nonblocking {
        flags | libc::O_NONBLOCK
    } else {
        flags & !libc::O_NONBLOCK
    };
    let result = unsafe { libc::fcntl(fd, libc::F_SETFL, next) };
    if result < 0 {
        return Err(to_error(io::Error::last_os_error()));
    }
    Ok(())
}

fn create_pipe() -> Result<(OwnedFd, OwnedFd)> {
    let mut fds = [-1; 2];
    let result = unsafe { libc::pipe(fds.as_mut_ptr()) };
    if result < 0 {
        return Err(to_error(io::Error::last_os_error()));
    }

    let read_fd = unsafe { OwnedFd::from_raw_fd(fds[0]) };
    let write_fd = unsafe { OwnedFd::from_raw_fd(fds[1]) };
    if let Err(err) = set_nonblocking(write_fd.as_raw_fd(), true) {
        return Err(err);
    }
    Ok((read_fd, write_fd))
}

fn write_stop_signal(fd: RawFd) -> io::Result<()> {
    let buffer = [1u8; 1];
    let result = unsafe { libc::write(fd, buffer.as_ptr().cast(), buffer.len()) };
    if result < 0 {
        let err = io::Error::last_os_error();
        if is_retry(&err) {
            return Ok(());
        }
        return Err(err);
    }
    Ok(())
}

fn wireguard_message_type(data: &[u8]) -> Option<u32> {
    if data.len() < 4 {
        return None;
    }
    Some(u32::from_le_bytes([data[0], data[1], data[2], data[3]]))
}

fn should_drop_quiet_tun_packet(packet: &[u8]) -> bool {
    if packet.is_empty() {
        return true;
    }

    match packet[0] >> 4 {
        4 => should_drop_quiet_ipv4_packet(packet),
        6 => should_drop_quiet_ipv6_packet(packet),
        _ => true,
    }
}

fn should_drop_quiet_ipv4_packet(packet: &[u8]) -> bool {
    if packet.len() < 20 {
        return true;
    }

    let header_len = usize::from(packet[0] & 0x0f) * 4;
    if header_len < 20 || packet.len() < header_len {
        return true;
    }

    let protocol = packet[9];
    let src = [packet[12], packet[13], packet[14], packet[15]];
    let dst = [packet[16], packet[17], packet[18], packet[19]];
    if is_ipv4_link_local(src) || is_ipv4_local_broadcast(dst) || is_ipv4_multicast(dst) {
        return true;
    }

    if protocol == libc::IPPROTO_UDP as u8 {
        return should_drop_quiet_udp_packet(&packet[header_len..]);
    }

    false
}

fn should_drop_quiet_ipv6_packet(packet: &[u8]) -> bool {
    if packet.len() < 40 {
        return true;
    }

    let next_header = packet[6];
    let src = &packet[8..24];
    let dst = &packet[24..40];
    if is_ipv6_link_local(src) || is_ipv6_multicast(dst) {
        return true;
    }

    if next_header == libc::IPPROTO_UDP as u8 {
        return should_drop_quiet_udp_packet(&packet[40..]);
    }

    false
}

fn should_drop_quiet_udp_packet(payload: &[u8]) -> bool {
    if payload.len() < 8 {
        return true;
    }

    let src_port = u16::from_be_bytes([payload[0], payload[1]]);
    let dst_port = u16::from_be_bytes([payload[2], payload[3]]);
    matches!(
        src_port,
        137 | 138 | 1900 | 5353 | 5355
    ) || matches!(dst_port, 137 | 138 | 1900 | 5353 | 5355)
}

fn is_ipv4_link_local(addr: [u8; 4]) -> bool {
    addr[0] == 169 && addr[1] == 254
}

fn is_ipv4_multicast(addr: [u8; 4]) -> bool {
    (224..=239).contains(&addr[0])
}

fn is_ipv4_local_broadcast(addr: [u8; 4]) -> bool {
    addr == [255, 255, 255, 255]
}

fn is_ipv6_link_local(addr: &[u8]) -> bool {
    addr.len() >= 2 && addr[0] == 0xfe && (addr[1] & 0xc0) == 0x80
}

fn is_ipv6_multicast(addr: &[u8]) -> bool {
    !addr.is_empty() && addr[0] == 0xff
}

fn close_if_valid(fd: RawFd) {
    if fd >= 0 {
        unsafe {
            libc::close(fd);
        }
    }
}

fn is_retry(err: &io::Error) -> bool {
    err.kind() == io::ErrorKind::WouldBlock || err.kind() == io::ErrorKind::Interrupted
}

fn to_error(err: io::Error) -> Error {
    error(err.to_string())
}

fn error(reason: impl Into<String>) -> Error {
    Error::from_reason(reason.into())
}
