#!/usr/bin/env python3
"""Host fixtures for the NPU RPC; no real sysfs, /proc or hardware access."""
import json
import os
import re
from pathlib import Path
import shlex
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
RPC = ROOT / 'luci-app-airoha-npu/root/usr/libexec/rpcd/luci.airoha_npu'


class NpuRpc(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='hg-npu-rpc-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.bound = self.root / 'sys/bus/platform/drivers/airoha-npu/1e900000.npu'
        self.bound.mkdir(parents=True)
        self.write('dmesg.txt', '')
        self.write('proc/interrupts', '')
        self.jshn = Path(os.environ.get('HG_JSHN_SH', ROOT / 'staging_dir/host/share/libubox/jshn.sh'))
        source = RPC.read_text().split('\ncase "$1" in\n', 1)[0]
        self.assertNotIn('case "$1" in', source)
        source = source.replace('. /lib/functions.sh', ': # no router shell library')
        source = re.sub(r'/(?:sys|proc|lib/firmware|tmp)/',
                        lambda m: str(self.root) + m[0], source)
        source = source.replace('/usr/share/libubox/jshn.sh', str(self.jshn))
        # Override commands that can access hardware; only fixture logs remain.
        source = source.replace('/usr/sbin/airoha-mcastctl', str(self.root / 'mcastctl'))
        source += '\ndmesg() { cat ' + shlex.quote(str(self.root / 'dmesg.txt')) + '; }\n'
        source += '_devmem_read() { echo 0; }\n_sample_cpu_usage() { _cpu_usage_json="[]"; }\n'
        self.script = self.root / 'rpc.sh'
        self.script.write_text(source)

    def write(self, path, data):
        p = self.root / path
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(data)
        return p

    def attrs(self, version='1456.62\n', cores='8\n'):
        (self.bound / 'fw_version').write_text(version)
        (self.bound / 'num_cores').write_text(cores)

    def run_rpc(self, command):
        env = dict(os.environ)
        env['PATH'] = str(self.jshn.parents[2] / 'bin') + ':/usr/bin:/bin'
        result = subprocess.run(['/usr/bin/busybox', 'ash', '-c', '. "$1"\n' + command, 'fixture', str(self.script)],
                                text=True, capture_output=True, env=env, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
        return json.loads(result.stdout)

    def identity(self):
        return self.run_rpc('''_read_npu_identity
printf '{"version":"%s","source":"%s","cores":%s,"loaded":%s}' "$npu_ver" "$npu_version_source" "$npu_cores" "$npu_loaded"''')

    def filter_fixture(self, extra=''):
        self.write('tmp/.keep', '')
        self.write('proc/sys/kernel/random/boot_id', '12345678-1234-1234-1234-123456789abc\n')
        self.write('proc/uptime', '123.45 400.00\n')
        self.write('sys/kernel/debug/airoha_eth-test/pon_multicast_filter',
                   'automatic=1 active=1 broken=0 last_error=0\n' + extra)

    def test_filter_missing_and_old_driver(self):
        self.assertFalse(self.run_rpc('_get_multicast_filter_raw')['available'])
        self.filter_fixture('hardware_drops=9007199254740993\n')
        result = self.run_rpc('_get_multicast_filter_raw')
        self.assertTrue(result['available'])
        self.assertFalse(result['detailed'])
        self.assertEqual(result['hardware_drops'], '9007199254740993')
        self.assertEqual(result['state'], 'unknown')
        self.assertEqual(result['admissions'], [])

    def test_filter_applied_vlan_and_large_counters(self):
        self.filter_fixture('status_version=1 state=active generation=12 applied_generation=12 snapshot_current=1\n'
                            'applied_rules=3 rule_capacity=64 applied_lookups=6 lookup_capacity=32\n'
                            'hardware_drops=72057594037927935\n'
                            'admission tagged=1 vid=4001 bypass=0 groups=239.3.1.245,239.3.1.124,\n')
        result = self.run_rpc('get_multicast_filter')
        self.assertTrue(result['detailed'])
        self.assertEqual(result['generation'], '12')
        self.assertEqual(result['hardware_drops'], '72057594037927935')
        self.assertEqual(result['uptime'], 123.45)
        self.assertEqual(result['admissions'], [dict(tagged=1, vid=4001, bypass=0, groups=['239.3.1.245', '239.3.1.124'])])

    def test_filter_errors_never_become_zero(self):
        self.filter_fixture('status_version=1 state=capacity-exceeded snapshot_current=0\n'
                            'hardware_drops_error=-5\n')
        result = self.run_rpc('_get_multicast_filter_raw')
        self.assertNotIn('hardware_drops', result)
        self.assertEqual(result['hardware_drops_error'], -5)
        self.assertEqual(result['state'], 'capacity-exceeded')
        result = self.run_rpc('_run_with_deadline() { return 124; }\nget_multicast_filter')
        self.assertFalse(result['available'])
        self.assertIn('error', result)

    def test_filter_malformed_data_and_no_table_scan(self):
        self.filter_fixture('hardware_drops=bad\n'
                            'admission tagged=1 vid=4001 bypass=0 groups=239.1.1.1,invalid,239.999.0.1,\n')
        result = self.run_rpc('_get_multicast_filter_raw')
        self.assertNotIn('hardware_drops', result)
        self.assertEqual(result['admissions'][0]['groups'], ['239.1.1.1'])
        source = RPC.read_text().split('_get_multicast_filter_raw() {', 1)[1].split('\nget_multicast_filter()', 1)[0]
        self.assertEqual(source.count('raw=$(cat "$1")'), 1)
        for forbidden in ('/ppe/entries', 'devmem', 'uci ', 'ifc_request'):
            self.assertNotIn(forbidden, source)

    def test_sysfs_wins_over_logs(self):
        self.attrs()
        self.write('dmesg.txt', 'airoha-npu 1e900000.npu: NPU fw version: 1.2\n')
        self.assertEqual(self.identity(), dict(version='1456.62', source='driver', cores=8, loaded=True))

    def test_zero_version_is_valid(self):
        self.attrs('0.0\n')
        self.assertEqual(self.identity()['version'], '0.0')

    def test_failed_attribute_does_not_use_stale_log(self):
        self.attrs('')
        self.write('dmesg.txt', 'airoha-npu 1e900000.npu: NPU fw version: 1.2\n')
        self.assertEqual(self.identity()['source'], 'unknown')

    def test_malformed_attributes_are_not_json(self):
        self.attrs('bad"version\n', '8\n99\n')
        data = self.identity()
        self.assertEqual(data['version'], 'Unknown')
        self.assertIsNone(data['cores'])

    def test_zero_missing_or_invalid_core_count_is_unknown(self):
        for cores in ('0\n', '-1\n', '65536\n', 'abc\n', ''):
            with self.subTest(cores=cores):
                self.attrs(cores=cores)
                self.assertIsNone(self.identity()['cores'])

    def test_multiline_version_is_unknown(self):
        self.attrs('1.2\n3.4\n')
        self.assertEqual(self.identity()['source'], 'unknown')

    def test_legacy_log_is_device_scoped(self):
        self.write('dmesg.txt', '[1] airoha-npu 1e900000.npu: NPU fw version: 1456.62\n'
                   '[2] airoha-npu 2e900000.npu: NPU fw version: 999.1\n')
        self.write('proc/interrupts', '1: 0 0 GIC airoha-npu-wdt\n2: 0 0 GIC airoha-npu-wdt\n')
        self.assertEqual(self.identity(), dict(version='1456.62', source='boot_log', cores=2, loaded=True))

    def test_legacy_log_rotation_reports_unknown(self):
        self.assertEqual(self.identity(), dict(version='Unknown', source='unknown', cores=None, loaded=True))

    def test_legacy_firmware_file_has_explicit_source(self):
        (self.bound / 'of_node').mkdir()
        (self.bound / 'of_node/firmware-name').write_bytes(b'airoha/test_rv32.bin\0')
        self.write('lib/firmware/airoha/test_rv32.bin', 'test TLB1456.62-v1\n')
        data = self.identity()
        self.assertEqual(data['version'], 'TLB1456.62-v1')
        self.assertEqual(data['source'], 'firmware_file')

    def test_unbound_driver_does_not_claim_loaded_firmware(self):
        self.bound.rmdir()
        self.write('dmesg.txt', 'airoha-npu 1e900000.npu: NPU fw version: 1456.62\n')
        self.assertEqual(self.identity(), dict(version='Unknown', source='unknown', cores=None, loaded=False))

    def test_hardware_timeout_keeps_cached_identity(self):
        self.attrs()
        data = self.run_rpc('_run_with_deadline() { return 125; }\nget_status')
        self.assertEqual(data['npu_version'], '1456.62')
        self.assertEqual(data['npu_cores'], 8)
        self.assertTrue(data['npu_loaded'])
        self.assertIn('error', data)

    def test_hardware_timeout_legacy_fallback_is_unknown(self):
        self.write('dmesg.txt', 'airoha-npu 1e900000.npu: NPU fw version: 1456.62\n')
        data = self.run_rpc('_run_with_deadline() { return 125; }\nget_status')
        self.assertEqual(data['npu_version_source'], 'unknown')
        self.assertIsNone(data['npu_cores'])

    def test_complete_status_json_uses_identity(self):
        self.attrs()
        data = self.run_rpc('_get_status_raw')
        self.assertEqual(data['npu_version_source'], 'driver')
        self.assertEqual(data['npu_cores'], 8)
        self.assertEqual(data['memory_regions'], [])

    def test_topology_hg_and_optional_wifi(self):
        self.assertTrue(self.jshn.is_file(), 'Build host jshn or set HG_JSHN_SH')
        for name, unit, mode, pon in [('eth0', 'ethernet@1', 'internal', False),
                                      ('pon0', 'ethernet@2/ethernet-port@0', 'xgmii', True),
                                      ('lan1', 'ethernet@4', '2500base-x', False)]:
            node = self.root / 'sys/firmware/devicetree/base/soc' / unit
            node.mkdir(parents=True, exist_ok=True)
            (node / 'phy-mode').write_bytes(mode.encode() + b'\0')
            if pon:
                (node.parent / 'airoha,pon-data-path').touch()
            net = self.root / 'sys/class/net' / name
            net.mkdir(parents=True)
            (net / 'of_node').symlink_to(node)
            (net / 'ifindex').write_text('2\n' if name == 'eth0' else '3\n')
        for number in (2, 3, 4):
            node = self.root / f'sys/firmware/devicetree/base/soc/switch/ports/port@{number}'
            node.mkdir(parents=True)
            net = self.root / f'sys/class/net/lan{number}'
            net.mkdir()
            (net / 'of_node').symlink_to(node)
            (net / 'iflink').write_text('2\n')
        data = self.run_rpc('get_topology')
        self.assertFalse(data['has_wifi'])
        self.assertEqual(data['gdm']['gdm1'][0]['switch_ports'], ['lan2', 'lan3', 'lan4'])
        self.assertTrue(data['gdm']['gdm2'][0]['pon'])
        self.assertEqual(data['gdm']['gdm4'][0]['phy_mode'], '2500base-x')
        (self.root / 'sys/class/ieee80211/phy0').mkdir(parents=True)
        self.assertTrue(self.run_rpc('get_topology')['has_wifi'])

    def test_multicast_controller_absent(self):
        self.assertEqual(self.run_rpc('get_multicast')['error'], 'multicast_controller_unavailable')

    def test_multicast_read_only_status(self):
        self.write('mcastctl', '#!/bin/sh\nexit 0\n').chmod(0o700)
        data = self.run_rpc('''_run_with_deadline() {
            [ "$3" = "''' + str(self.root/'mcastctl') + '''" ] && [ "$4" = get ] || return 1
            printf '%s' '{"enabled":1,"frozen":1,"running":1,"active":0,"reject":{"bridge":4}}'
        }
        uci() { case "$*" in *enabled) echo 1;; *upstream) echo iptv;; *downstream) echo lan;; esac; }
        get_multicast''')
        self.assertEqual(data['active'], 0)
        self.assertEqual(data['reject']['bridge'], 4)
        self.assertEqual(data['configured_upstream'], 'iptv')

    def test_multicast_timeout_is_not_disabled(self):
        self.write('mcastctl', '#!/bin/sh\nexit 0\n').chmod(0o700)
        self.assertEqual(self.run_rpc('_run_with_deadline() { return 125; }\nget_multicast')['error'],
                         'multicast_status_unavailable')


if __name__ == '__main__':
    unittest.main(verbosity=2)
