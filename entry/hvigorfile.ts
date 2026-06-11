import { hapTasks } from '@ohos/hvigor-ohos-plugin';
import type { HvigorNode, HvigorPlugin } from '@ohos/hvigor';
import { spawnSync } from 'child_process';
import * as fs from 'fs';
import * as path from 'path';
import * as process from 'process';

const BUILD_WG_NATIVE_TASK = 'BuildWireGuardNative';
const PROCESS_LIBS_TASK = 'default@ProcessLibs';

const buildWireGuardNativePlugin: HvigorPlugin = {
  pluginId: 'wg-agent-native',
  apply(node: HvigorNode): void {
    node.registerTask({
      name: BUILD_WG_NATIVE_TASK,
      run: (): void => {
        const moduleDir = node.getNodeDir().getPath();
        const projectDir = path.resolve(moduleDir, '..');
        const scriptPath = path.resolve(projectDir, 'scripts', 'build_native.js');
        const result = spawnSync(process.execPath, [scriptPath], {
          cwd: projectDir,
          stdio: 'inherit'
        });
        if (result.error !== undefined) {
          throw result.error;
        }
        if (result.status !== 0) {
          throw new Error('BuildWireGuardNative failed with exit code ' + String(result.status));
        }

        const soPath = path.resolve(moduleDir, 'libs', 'arm64-v8a', 'libwg_boringtun.so');
        if (!fs.existsSync(soPath)) {
          throw new Error('libwg_boringtun.so was not generated at ' + soPath);
        }
      },
      postDependencies: [PROCESS_LIBS_TASK]
    });
  }
};

export default {
  system: hapTasks,
  plugins: [buildWireGuardNativePlugin]
};
