use std::collections::HashMap;
use std::io;
use std::net::{SocketAddr, ToSocketAddrs, UdpSocket};
use std::os::fd::{AsRawFd, FromRawFd, OwnedFd, RawFd};
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{Arc, Mutex, MutexGuard};
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
const MAX_IP_PACKET_SIZE: usize = 65_535;
const WG_BUFFER_PADDING: usize = 512;
const WG_BUFFER_SIZE: usize = MAX_IP_PACKET_SIZE + WG_BUFFER_PADDING;
const HANDSHAKE_INDEX: u32 = 1;
const WG_MESSAGE_HANDSHAKE_INITIATION: u32 = 1;
const WG_MESSAGE_DATA: u32 = 4;
const REKEY_TIMEOUT_MS: u64 = 5_000;
const KEEPALIVE_TIMEOUT_MS: u64 = 10_000;
const DATA_SILENCE_REKEY_MS: u64 = 15_000;
const MIN_TIMER_DELAY_MS: u64 = 500;
const QOS_BACKGROUND: libc::c_int = 0;

static NEXT_HANDLE: AtomicU64 = AtomicU64::new(1);
static GLOBAL_TICK_COUNT: AtomicU64 = AtomicU64::new(0);
static REGISTRY: Lazy<Mutex<HashMap<u64, Arc<TunnelRuntime>>>> =
    Lazy::new(|| Mutex::new(HashMap::new()));

unsafe extern "C" {
    fn OH_QoS_SetThreadQoS(level: libc::c_int) -> libc::c_int;
    fn OH_QoS_ResetThreadQoS() -> libc::c_int;
}

#[napi(object)]
pub struct NativeTunnelStats {
    pub running: bool,
    pub tx_bytes: f64,
    pub rx_bytes: f64,
    pub latest_handshake_seconds: f64,
    pub latest_packet_sent_seconds: f64,
    pub loss: f64,
    pub rtt_millis: f64,
    pub tun_read_packets: f64,
    pub tun_dropped_packets: f64,
    pub udp_read_packets: f64,
    pub tun_write_packets: f64,
    pub tun_read_last: String,
    pub tun_write_last: String,
}

struct TunnelRuntime {
    socket: UdpSocket,
    peer_addr: SocketAddr,
    tunn: Mutex<Tunn>,
    mtu: usize,
    persistent_keepalive_ms: u64,
    running: AtomicBool,
    last_network_send_ms: AtomicU64,
    tun_read_packets: AtomicU64,
    tun_dropped_packets: AtomicU64,
    udp_read_packets: AtomicU64,
    tun_write_packets: AtomicU64,
    packet_summaries: Mutex<PacketSummaries>,
    tick_count: AtomicU64,
    timer_state: Mutex<TimerState>,
    workers: Mutex<Vec<JoinHandle<()>>>,
    stop_writers: Mutex<Vec<OwnedFd>>,
    timer_wake_fd: Mutex<Option<RawFd>>,
}

struct TimerState {
    deadlines_ms: Vec<u64>,
}

struct PacketSummaries {
    tun_read_last: String,
    tun_write_last: String,
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
        tun_read_packets: AtomicU64::new(0),
        tun_dropped_packets: AtomicU64::new(0),
        udp_read_packets: AtomicU64::new(0),
        tun_write_packets: AtomicU64::new(0),
        packet_summaries: Mutex::new(PacketSummaries {
            tun_read_last: String::new(),
            tun_write_last: String::new(),
        }),
        tick_count: AtomicU64::new(0),
        timer_state: Mutex::new(TimerState {
            deadlines_ms: Vec::new(),
        }),
        workers: Mutex::new(Vec::new()),
        stop_writers: Mutex::new(Vec::new()),
        timer_wake_fd: Mutex::new(None),
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
    let packet_summaries = runtime
        .packet_summaries
        .lock()
        .map_err(|_| error("packet summaries lock poisoned"))?;

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
        tun_read_packets: runtime.tun_read_packets.load(Ordering::SeqCst) as f64,
        tun_dropped_packets: runtime.tun_dropped_packets.load(Ordering::SeqCst) as f64,
        udp_read_packets: runtime.udp_read_packets.load(Ordering::SeqCst) as f64,
        tun_write_packets: runtime.tun_write_packets.load(Ordering::SeqCst) as f64,
        tun_read_last: packet_summaries.tun_read_last.clone(),
        tun_write_last: packet_summaries.tun_write_last.clone(),
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
        if let Err(err) = self.set_timer_wake_fd(Some(udp_stop_write.as_raw_fd())) {
            self.running.store(false, Ordering::SeqCst);
            return Err(err);
        }

        let tun_read_runtime = self.clone();
        let tun_worker = match thread::Builder::new()
            .name("wg-tun-reader".to_string())
            .spawn(move || {
                let _qos = ThreadQosGuard::new(QOS_BACKGROUND);
                tun_read_runtime.tun_reader_loop(tun_for_read, tun_stop_read, socket_for_write);
            })
            .map_err(to_error) {
            Ok(worker) => worker,
            Err(err) => {
                self.running.store(false, Ordering::SeqCst);
                let _ = self.set_timer_wake_fd(None);
                return Err(err);
            }
        };

        let udp_runtime = self.clone();
        let udp_worker = match thread::Builder::new()
            .name("wg-udp-reader".to_string())
            .spawn(move || {
                let _qos = ThreadQosGuard::new(QOS_BACKGROUND);
                udp_runtime.udp_reader_loop(socket_for_read, udp_stop_read, tun_for_write);
            })
            .map_err(to_error) {
            Ok(worker) => worker,
            Err(err) => {
                self.running.store(false, Ordering::SeqCst);
                let _ = self.set_timer_wake_fd(None);
                let _ = write_stop_signal(tun_stop_write.as_raw_fd());
                let _ = tun_worker.join();
                return Err(err);
            }
        };

        let mut workers = match self.lock_workers() {
            Ok(workers) => workers,
            Err(err) => {
                self.running.store(false, Ordering::SeqCst);
                let _ = self.set_timer_wake_fd(None);
                let _ = write_stop_signal(tun_stop_write.as_raw_fd());
                let _ = write_stop_signal(udp_stop_write.as_raw_fd());
                let _ = tun_worker.join();
                let _ = udp_worker.join();
                return Err(err);
            }
        };
        let mut stop_writers = match self.lock_stop_writers() {
            Ok(stop_writers) => stop_writers,
            Err(err) => {
                self.running.store(false, Ordering::SeqCst);
                let _ = self.set_timer_wake_fd(None);
                let _ = write_stop_signal(tun_stop_write.as_raw_fd());
                let _ = write_stop_signal(udp_stop_write.as_raw_fd());
                let _ = tun_worker.join();
                let _ = udp_worker.join();
                return Err(err);
            }
        };
        stop_writers.push(tun_stop_write);
        stop_writers.push(udp_stop_write);
        workers.push(tun_worker);
        workers.push(udp_worker);
        drop(stop_writers);
        drop(workers);
        self.schedule_persistent_keepalive();
        self.send_initial_handshake();
        Ok(())
    }

    fn stop(&self) {
        self.running.store(false, Ordering::SeqCst);
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
        let _ = self.set_timer_wake_fd(None);
    }

    fn tun_reader_loop(&self, tun_fd: OwnedFd, stop_fd: OwnedFd, socket: UdpSocket) {
        let mut packet = vec![0u8; MAX_IP_PACKET_SIZE];
        let mut out = vec![0u8; WG_BUFFER_SIZE];

        while self.running.load(Ordering::SeqCst) {
            match poll_readable_or_stop(tun_fd.as_raw_fd(), stop_fd.as_raw_fd(), -1) {
                Ok(PollOutcome::Ready) => {}
                Ok(PollOutcome::Stopped) => break,
                Ok(PollOutcome::TimedOut) => continue,
                Err(err) if is_retry(&err) => continue,
                Err(_) => break,
            }
            self.bump_tick();

            match read_fd(tun_fd.as_raw_fd(), &mut packet) {
                Ok(0) => continue,
                Ok(size) => {
                    self.tun_read_packets.fetch_add(1, Ordering::SeqCst);
                    self.set_tun_read_last(&packet[..size]);
                    if should_drop_quiet_tun_packet(&packet[..size]) {
                        self.tun_dropped_packets.fetch_add(1, Ordering::SeqCst);
                        continue;
                    }
                    clamp_tcp_mss(&mut packet[..size], self.mtu);
                    let result = {
                        let mut tunn = match self.lock_tunn() {
                            Ok(tunn) => tunn,
                            Err(_) => break,
                        };
                        tunn.encapsulate(&packet[..size], &mut out)
                    };
                    self.handle_tunn_result(result, &socket, None);
                }
                Err(err) if is_retry(&err) => continue,
                Err(_) => break,
            }
        }
    }

    fn udp_reader_loop(&self, socket: UdpSocket, stop_fd: OwnedFd, tun_fd: OwnedFd) {
        let mut datagram = vec![0u8; WG_BUFFER_SIZE];
        let mut out = vec![0u8; WG_BUFFER_SIZE];

        'udp_loop: while self.running.load(Ordering::SeqCst) {
            match poll_readable_or_stop(
                socket.as_raw_fd(),
                stop_fd.as_raw_fd(),
                self.next_timer_timeout_ms(),
            ) {
                Ok(PollOutcome::Ready) => {
                    self.bump_tick();
                }
                Ok(PollOutcome::Stopped) => {
                    if self.running.load(Ordering::SeqCst) {
                        continue;
                    }
                    break;
                }
                Ok(PollOutcome::TimedOut) => {
                    self.bump_tick();
                    self.handle_due_timers(&socket, &mut out);
                    continue;
                }
                Err(err) if is_retry(&err) => continue,
                Err(_) => break,
            }

            match socket.recv_from(&mut datagram) {
                Ok((size, src)) => {
                    if src != self.peer_addr {
                        continue;
                    }
                    self.udp_read_packets.fetch_add(1, Ordering::SeqCst);

                    let received_message_type = wireguard_message_type(&datagram[..size]);
                    let result = {
                        let mut tunn = match self.lock_tunn() {
                            Ok(tunn) => tunn,
                            Err(_) => break,
                        };
                        tunn.decapsulate(Some(src.ip()), &datagram[..size], &mut out)
                    };
                    self.handle_tunn_result(result, &socket, Some(tun_fd.as_raw_fd()));

                    loop {
                        let result = {
                            let mut tunn = match self.lock_tunn() {
                                Ok(tunn) => tunn,
                                Err(_) => break 'udp_loop,
                            };
                            tunn.decapsulate(Some(src.ip()), &[], &mut out)
                        };
                        let flush_again = should_flush_again(&result);
                        let _ = self.handle_tunn_result(result, &socket, Some(tun_fd.as_raw_fd()));
                        if !flush_again {
                            break;
                        }
                    }
                    if received_message_type == Some(WG_MESSAGE_DATA) {
                        self.schedule_timer_after(Duration::from_millis(KEEPALIVE_TIMEOUT_MS));
                    }
                }
                Err(err) if is_retry(&err) => continue,
                Err(_) => break,
            }

            self.handle_due_timers(&socket, &mut out);
        }
    }

    fn send_initial_handshake(&self) {
        let mut out = vec![0u8; WG_BUFFER_SIZE];
        let result = {
            let mut tunn = match self.lock_tunn() {
                Ok(tunn) => tunn,
                Err(_) => return,
            };
            tunn.format_handshake_initiation(&mut out, false)
        };
        let _ = self.handle_tunn_result(result, &self.socket, None);
    }

    fn force_handshake(&self) -> Result<()> {
        let mut out = vec![0u8; WG_BUFFER_SIZE];
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
                    if write_all_fd(fd, data).is_ok() {
                        self.tun_write_packets.fetch_add(1, Ordering::SeqCst);
                        self.set_tun_write_last(data);
                    }
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
        let delay_ms = duration.as_millis().min(u64::MAX as u128) as u64;
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
            compact_deadlines(&mut state.deadlines_ms);
            if wake_earlier {
                self.wake_timer_owner();
            }
        }
    }

    fn next_timer_timeout_ms(&self) -> i32 {
        let mut state = match self.timer_state.lock() {
            Ok(state) => state,
            Err(_) => return -1,
        };
        let now = now_millis();
        compact_deadlines(&mut state.deadlines_ms);
        state
            .deadlines_ms
            .iter()
            .copied()
            .min()
            .map(|deadline| {
                if deadline <= now {
                    0
                } else {
                    let delay_ms = deadline - now;
                    delay_ms.min(i32::MAX as u64) as i32
                }
            })
            .unwrap_or(-1)
    }

    fn take_due_timer(&self) -> bool {
        let mut state = match self.timer_state.lock() {
            Ok(state) => state,
            Err(_) => return false,
        };
        let now = now_millis();
        if let Some(index) = state.deadlines_ms.iter().position(|deadline| *deadline <= now) {
            state.deadlines_ms.remove(index);
            return true;
        }
        false
    }

    fn handle_due_timers(&self, socket: &UdpSocket, out: &mut [u8]) {
        while self.take_due_timer() {
            let result = {
                let mut tunn = match self.lock_tunn() {
                    Ok(tunn) => tunn,
                    Err(_) => return,
                };
                tunn.update_timers(out)
            };
            if self.handle_tunn_result(result, socket, None) {
                self.schedule_persistent_keepalive();
            }
        }
    }

    fn set_timer_wake_fd(&self, fd: Option<RawFd>) -> Result<()> {
        let mut timer_wake_fd = self
            .timer_wake_fd
            .lock()
            .map_err(|_| error("timer wake fd lock poisoned"))?;
        *timer_wake_fd = fd;
        Ok(())
    }

    fn wake_timer_owner(&self) {
        let fd = self.timer_wake_fd.lock().ok().and_then(|timer_wake_fd| *timer_wake_fd);
        if let Some(fd) = fd {
            let _ = write_stop_signal(fd);
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

    fn set_tun_read_last(&self, packet: &[u8]) {
        self.set_packet_summary(packet, true);
    }

    fn set_tun_write_last(&self, packet: &[u8]) {
        self.set_packet_summary(packet, false);
    }

    fn set_packet_summary(&self, packet: &[u8], read_side: bool) {
        let summary = summarize_ip_packet(packet);
        if let Ok(mut packet_summaries) = self.packet_summaries.lock() {
            if read_side {
                packet_summaries.tun_read_last = summary;
            } else {
                packet_summaries.tun_write_last = summary;
            }
        }
    }

}

struct ThreadQosGuard {
    should_reset: bool,
}

impl ThreadQosGuard {
    fn new(level: libc::c_int) -> Self {
        let should_reset = unsafe { OH_QoS_SetThreadQoS(level) == 0 };
        Self { should_reset }
    }
}

impl Drop for ThreadQosGuard {
    fn drop(&mut self) {
        if self.should_reset {
            let _ = unsafe { OH_QoS_ResetThreadQoS() };
        }
    }
}

fn should_flush_again(result: &TunnResult<'_>) -> bool {
    matches!(result, TunnResult::WriteToNetwork(_))
}

fn summarize_ip_packet(packet: &[u8]) -> String {
    if packet.is_empty() {
        return "empty".to_string();
    }

    match packet[0] >> 4 {
        4 => summarize_ipv4_packet(packet),
        6 => summarize_ipv6_packet(packet),
        version => format!("ip_version_{}", version),
    }
}

fn summarize_ipv4_packet(packet: &[u8]) -> String {
    if packet.len() < 20 {
        return "ipv4_short".to_string();
    }

    let header_len = usize::from(packet[0] & 0x0f) * 4;
    if header_len < 20 || packet.len() < header_len {
        return "ipv4_bad_header".to_string();
    }

    let protocol = packet[9];
    let src = format_ipv4(&packet[12..16]);
    let dst = format_ipv4(&packet[16..20]);
    let total_len = usize::from(u16::from_be_bytes([packet[2], packet[3]]));
    summarize_transport_packet(
        "ipv4",
        protocol,
        &src,
        &dst,
        &packet[header_len..],
        total_len.min(packet.len()),
    )
}

fn summarize_ipv6_packet(packet: &[u8]) -> String {
    if packet.len() < 40 {
        return "ipv6_short".to_string();
    }

    let protocol = packet[6];
    let src = format_ipv6(&packet[8..24]);
    let dst = format_ipv6(&packet[24..40]);
    let payload_len = usize::from(u16::from_be_bytes([packet[4], packet[5]]));
    summarize_transport_packet(
        "ipv6",
        protocol,
        &src,
        &dst,
        &packet[40..],
        (40 + payload_len).min(packet.len()),
    )
}

fn summarize_transport_packet(
    family: &str,
    protocol: u8,
    src: &str,
    dst: &str,
    payload: &[u8],
    packet_len: usize,
) -> String {
    if protocol == libc::IPPROTO_TCP as u8 {
        if payload.len() < 4 {
            return format!("{} {} {} -> {} short", family, protocol_name(protocol), src, dst);
        }
        let src_port = u16::from_be_bytes([payload[0], payload[1]]);
        let dst_port = u16::from_be_bytes([payload[2], payload[3]]);
        let tcp_header_len = if payload.len() >= 13 {
            usize::from(payload[12] >> 4) * 4
        } else {
            0
        };
        let tcp_payload_len = payload.len().saturating_sub(tcp_header_len);
        let flags = if payload.len() >= 14 {
            format_tcp_flags(payload[13])
        } else {
            "?".to_string()
        };
        return format!(
            "{} tcp {}:{} -> {}:{} flags={} len={} data={}",
            family,
            src,
            src_port,
            dst,
            dst_port,
            flags,
            packet_len,
            tcp_payload_len
        );
    }

    if protocol == libc::IPPROTO_UDP as u8 {
        if payload.len() < 8 {
            return format!("{} udp {} -> {} short", family, src, dst);
        }
        let src_port = u16::from_be_bytes([payload[0], payload[1]]);
        let dst_port = u16::from_be_bytes([payload[2], payload[3]]);
        return format!(
            "{} udp {}:{} -> {}:{} len={}",
            family, src, src_port, dst, dst_port, packet_len
        );
    }

    if protocol == libc::IPPROTO_ICMP as u8 || protocol == libc::IPPROTO_ICMPV6 as u8 {
        return format!("{} {} {} -> {}", family, protocol_name(protocol), src, dst);
    }

    format!("{} proto{} {} -> {}", family, protocol, src, dst)
}

fn format_tcp_flags(flags: u8) -> String {
    let mut names: Vec<&str> = Vec::new();
    if flags & 0x02 != 0 {
        names.push("SYN");
    }
    if flags & 0x10 != 0 {
        names.push("ACK");
    }
    if flags & 0x08 != 0 {
        names.push("PSH");
    }
    if flags & 0x01 != 0 {
        names.push("FIN");
    }
    if flags & 0x04 != 0 {
        names.push("RST");
    }
    if names.is_empty() {
        return "NONE".to_string();
    }
    names.join("|")
}

fn protocol_name(protocol: u8) -> &'static str {
    if protocol == libc::IPPROTO_TCP as u8 {
        return "tcp";
    }
    if protocol == libc::IPPROTO_UDP as u8 {
        return "udp";
    }
    if protocol == libc::IPPROTO_ICMP as u8 {
        return "icmp";
    }
    if protocol == libc::IPPROTO_ICMPV6 as u8 {
        return "icmpv6";
    }
    "other"
}

fn format_ipv4(addr: &[u8]) -> String {
    if addr.len() < 4 {
        return "?".to_string();
    }
    format!("{}.{}.{}.{}", addr[0], addr[1], addr[2], addr[3])
}

fn format_ipv6(addr: &[u8]) -> String {
    if addr.len() < 16 {
        return "?".to_string();
    }
    let mut parts: Vec<String> = Vec::new();
    for index in 0..8 {
        let offset = index * 2;
        let part = u16::from_be_bytes([addr[offset], addr[offset + 1]]);
        parts.push(format!("{:x}", part));
    }
    parts.join(":")
}

fn clamp_tcp_mss(packet: &mut [u8], mtu: usize) -> bool {
    if packet.is_empty() {
        return false;
    }

    match packet[0] >> 4 {
        4 => clamp_ipv4_tcp_mss(packet, mtu),
        6 => clamp_ipv6_tcp_mss(packet, mtu),
        _ => false,
    }
}

fn clamp_ipv4_tcp_mss(packet: &mut [u8], mtu: usize) -> bool {
    if packet.len() < 20 || packet[9] != libc::IPPROTO_TCP as u8 {
        return false;
    }

    let ip_header_len = usize::from(packet[0] & 0x0f) * 4;
    let total_len = usize::from(u16::from_be_bytes([packet[2], packet[3]]));
    if ip_header_len < 20 || total_len < ip_header_len + 20 || packet.len() < total_len {
        return false;
    }

    let max_mss = match tcp_mss_for_mtu(mtu, 20) {
        Some(value) => value,
        None => return false,
    };
    if clamp_tcp_mss_option(packet, ip_header_len, total_len, max_mss) {
        write_ipv4_tcp_checksum(packet, ip_header_len, total_len);
        return true;
    }
    false
}

fn clamp_ipv6_tcp_mss(packet: &mut [u8], mtu: usize) -> bool {
    if packet.len() < 40 || packet[6] != libc::IPPROTO_TCP as u8 {
        return false;
    }

    let payload_len = usize::from(u16::from_be_bytes([packet[4], packet[5]]));
    let total_len = 40 + payload_len;
    if total_len < 60 || packet.len() < total_len {
        return false;
    }

    let max_mss = match tcp_mss_for_mtu(mtu, 40) {
        Some(value) => value,
        None => return false,
    };
    if clamp_tcp_mss_option(packet, 40, total_len, max_mss) {
        write_ipv6_tcp_checksum(packet, 40, total_len);
        return true;
    }
    false
}

fn tcp_mss_for_mtu(mtu: usize, ip_header_len: usize) -> Option<u16> {
    mtu.checked_sub(ip_header_len + 20)
        .and_then(|value| u16::try_from(value).ok())
}

fn clamp_tcp_mss_option(
    packet: &mut [u8],
    tcp_start: usize,
    tcp_end: usize,
    max_mss: u16,
) -> bool {
    if packet.len() < tcp_start + 20 || tcp_end < tcp_start + 20 || tcp_end > packet.len() {
        return false;
    }
    if packet[tcp_start + 13] & 0x02 == 0 {
        return false;
    }

    let tcp_header_len = usize::from(packet[tcp_start + 12] >> 4) * 4;
    if tcp_header_len < 20 || tcp_start + tcp_header_len > tcp_end {
        return false;
    }

    let mut index = tcp_start + 20;
    let options_end = tcp_start + tcp_header_len;
    while index < options_end {
        let kind = packet[index];
        if kind == 0 {
            break;
        }
        if kind == 1 {
            index += 1;
            continue;
        }
        if index + 1 >= options_end {
            break;
        }

        let option_len = usize::from(packet[index + 1]);
        if option_len < 2 || index + option_len > options_end {
            break;
        }
        if kind == 2 && option_len == 4 {
            let current = u16::from_be_bytes([packet[index + 2], packet[index + 3]]);
            if current > max_mss {
                let clamped = max_mss.to_be_bytes();
                packet[index + 2] = clamped[0];
                packet[index + 3] = clamped[1];
                return true;
            }
            return false;
        }
        index += option_len;
    }
    false
}

fn write_ipv4_tcp_checksum(packet: &mut [u8], ip_header_len: usize, total_len: usize) {
    let tcp_start = ip_header_len;
    packet[tcp_start + 16] = 0;
    packet[tcp_start + 17] = 0;

    let tcp_len = total_len - tcp_start;
    let mut sum = 0u32;
    sum = add_checksum_bytes(sum, &packet[12..16]);
    sum = add_checksum_bytes(sum, &packet[16..20]);
    sum = add_checksum_bytes(sum, &[0, libc::IPPROTO_TCP as u8]);
    sum = add_checksum_bytes(sum, &(tcp_len as u16).to_be_bytes());
    sum = add_checksum_bytes(sum, &packet[tcp_start..total_len]);

    let checksum = finish_checksum(sum).to_be_bytes();
    packet[tcp_start + 16] = checksum[0];
    packet[tcp_start + 17] = checksum[1];
}

fn write_ipv6_tcp_checksum(packet: &mut [u8], tcp_start: usize, total_len: usize) {
    packet[tcp_start + 16] = 0;
    packet[tcp_start + 17] = 0;

    let tcp_len = total_len - tcp_start;
    let mut sum = 0u32;
    sum = add_checksum_bytes(sum, &packet[8..24]);
    sum = add_checksum_bytes(sum, &packet[24..40]);
    sum = add_checksum_bytes(sum, &(tcp_len as u32).to_be_bytes());
    sum = add_checksum_bytes(sum, &[0, 0, 0, libc::IPPROTO_TCP as u8]);
    sum = add_checksum_bytes(sum, &packet[tcp_start..total_len]);

    let checksum = finish_checksum(sum).to_be_bytes();
    packet[tcp_start + 16] = checksum[0];
    packet[tcp_start + 17] = checksum[1];
}

fn add_checksum_bytes(mut sum: u32, data: &[u8]) -> u32 {
    let mut chunks = data.chunks_exact(2);
    for chunk in &mut chunks {
        sum = sum.wrapping_add(u32::from(u16::from_be_bytes([chunk[0], chunk[1]])));
    }
    if let Some(byte) = chunks.remainder().first() {
        sum = sum.wrapping_add(u32::from(u16::from_be_bytes([*byte, 0])));
    }
    sum
}

fn finish_checksum(mut sum: u32) -> u16 {
    while sum >> 16 != 0 {
        sum = (sum & 0xffff) + (sum >> 16);
    }
    !(sum as u16)
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

fn compact_deadlines(deadlines: &mut Vec<u64>) {
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
    TimedOut,
}

fn poll_readable_or_stop(fd: RawFd, stop_fd: RawFd, timeout_ms: i32) -> io::Result<PollOutcome> {
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
    let result = unsafe {
        libc::poll(
            poll_fds.as_mut_ptr(),
            poll_fds.len() as libc::nfds_t,
            timeout_ms,
        )
    };
    if result < 0 {
        return Err(io::Error::last_os_error());
    }
    if result == 0 {
        return Ok(PollOutcome::TimedOut);
    }
    if poll_fds[1].revents & (libc::POLLIN | libc::POLLERR | libc::POLLHUP | libc::POLLNVAL) != 0
    {
        let _ = drain_fd(stop_fd);
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

fn drain_fd(fd: RawFd) -> io::Result<()> {
    let mut buffer = [0u8; 64];
    loop {
        let result = unsafe { libc::read(fd, buffer.as_mut_ptr().cast(), buffer.len()) };
        if result > 0 {
            continue;
        }
        if result == 0 {
            return Ok(());
        }

        let err = io::Error::last_os_error();
        if is_retry(&err) {
            return Ok(());
        }
        return Err(err);
    }
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
    if let Err(err) = set_nonblocking(read_fd.as_raw_fd(), true) {
        return Err(err);
    }
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
