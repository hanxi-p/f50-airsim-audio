"""tools/make-extra.sh: the release files - mu300-audio.tar.gz with the drivers of every kernel of kernel/kits/kits.lock,
in the layout mu300-update's extra_unpack takes from an extra of one's own (plain names, at most four levels, files and
directories only, ./VERSION, ./requires, ./name, ./manifest, the hooks), the same bytes for the same inputs, and no
firmware."""
import hashlib
import io
import os
import re
import subprocess
import tarfile
import tempfile
import unittest
from pathlib import Path

from helpers import TOP

LOCK = TOP / 'kernel' / 'kits' / 'kits.lock'
ENTRY = re.compile(r'\.|\./[A-Za-z0-9_+-][A-Za-z0-9._+-]*(/[A-Za-z0-9_+-][A-Za-z0-9._+-]*){0,3}')   # mu300-update MODULE_ENTRY


def kits():
    return [l.split() for l in LOCK.read_text().splitlines() if l.strip() and not l.startswith('#')]


def primaries():
    """the first line of each kernel: the kernel of the current mu300-linux release (later lines: earlier builds)"""
    seen = {}
    for k in kits():
        seen.setdefault(k[0], k)
    return list(seen.values())


def tag_key(tag):
    """a mu300-linux release tag (vYYYY.MM.DD[.N]) in order; a build of main (main-<commit>) after every release"""
    if tag.startswith('main-'):
        return (9999,)
    return tuple(int(x) for x in tag[1:].split('.'))


class Release(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = Path(tempfile.mkdtemp())
        cls.out = cls.tmp / 'a'
        env = dict(os.environ, MU300_AUDIO_FAKE='1', SOURCE_DATE_EPOCH='1700000000')
        subprocess.run(['sh', str(TOP / 'tools/make-extra.sh'), str(cls.out), 'v1.2.3'], check=True, capture_output=True, env=env)
        subprocess.run(['sh', str(TOP / 'tools/make-extra.sh'), str(cls.tmp / 'b'), 'v1.2.3'], check=True, capture_output=True, env=env)

    @classmethod
    def tearDownClass(cls):
        subprocess.run(['rm', '-rf', str(cls.tmp)])

    def test_one_tarball_for_every_kernel_of_the_lock(self):
        self.assertEqual([k[0] for k in primaries()], ['5.4', '6.18', '7.2', '7.3'])
        names = sorted(p.name for p in self.out.iterdir())
        self.assertEqual(names, ['SHA256SUMS', 'VERSIONS', 'mu300-audio.tar.gz'])
        sums = dict(reversed(l.split('  ')) for l in (self.out / 'SHA256SUMS').read_text().splitlines())
        for n, h in sums.items():
            self.assertEqual(hashlib.sha256((self.out / n).read_bytes()).hexdigest(), h)

    def test_the_layout_extra_unpack_takes(self):
        with tarfile.open(self.out / 'mu300-audio.tar.gz') as t:
            members = t.getmembers()
            for m in members:
                self.assertTrue(m.isfile() or m.isdir(), m.name)
                self.assertRegex(m.name.rstrip('/'), ENTRY)
                self.assertEqual((m.uid, m.gid), (0, 0))
                if m.isfile():
                    self.assertEqual(m.mode, 0o755 if m.name.startswith(('./bin/', './hooks/', './service/procd/')) else 0o644, m.name)
            files = {m.name: t.extractfile(m).read() for m in members if m.isfile()}
        self.assertEqual(files['./VERSION'], b'v1.2.3\n')
        self.assertEqual(files['./release'], b'v1.2.3\n')
        # not "audio": mu300-extra takes that name for retiring the old extra
        self.assertEqual(files['./name'], b'mu300-audio\n')
        self.assertNotIn('./kernel', files)
        need = (TOP / 'kernel' / 'kits' / 'requires').read_text().split()[0]
        self.assertEqual(files['./requires'], f'mu300-linux {need}\n'.encode())
        sets = {n.split('/')[2] for n in files if n.startswith('./modules/')}
        want = set()
        for key in {k[0] for k in kits()}:
            lines = [k for k in kits() if k[0] == key]
            want |= {lines[0][1]} | {f'{k[1]}+{k[2][:12]}' for k in lines[1:]}
            self.assertIn(f'CONFIG={lines[0][2]}\n'.encode(), files[f'./modules/{lines[0][1]}/KERNEL'])
            for k in lines[1:]:
                self.assertIn(f'CONFIG={k[2]}\nTAG={k[4]}\n'.encode(), files[f'./modules/{k[1]}+{k[2][:12]}/KERNEL'])
        self.assertEqual(sets, want)
        for b in ('mu300-audio-dsp', 'mu300-voice', 'pcmhost', 'ctlset', 'mu300-hfp'):
            self.assertIn(f'./bin/{b}', files)
        for s in ('mu300-audio', 'mu300-voice', 'mu300-audio-reserve'):
            self.assertIn(f'./service/systemd/{s}.service', files)
            self.assertIn(f'./service/procd/{s}', files)
        for h in ('link', 'unlink'):
            self.assertEqual(files[f'./hooks/{h}'], (TOP / 'hooks' / h).read_bytes())
        # the manifest lists every other file with its hash
        man = dict(reversed(l.split('  ')) for l in files['./manifest'].decode().splitlines())
        self.assertEqual(set(man), set(files) - {'./manifest'})
        for n, h in man.items():
            self.assertEqual(hashlib.sha256(files[n]).hexdigest(), h, n)
        # no firmware, ever
        for n, data in files.items():
            self.assertNotRegex(n.lower(), r'agdsp\.(bin|img)|firmware')
            self.assertLess(len(data), 1 << 20, n)

    def test_the_same_inputs_make_the_same_bytes(self):
        for f in self.out.iterdir():
            self.assertEqual(f.read_bytes(), (self.tmp / 'b' / f.name).read_bytes(), f.name)

    def test_versions(self):
        lines = (self.out / 'VERSIONS').read_text().splitlines()
        self.assertEqual(len(lines), 1)
        f = lines[0].split('\t')
        self.assertEqual((f[0], f[1], f[4]), ('mu300-audio', 'v1.2.3', 'mu300-audio.tar.gz'))
        self.assertEqual(f[3].split(), sorted({k[1] for k in kits()}))


class Lock(unittest.TestCase):
    def test_every_kernel_is_pinned(self):
        for key, krel, config, kit, tag in kits():
            self.assertRegex(config, r'^[0-9a-f]{64}$')
            self.assertRegex(kit, r'^[0-9a-f]{64}$')
            self.assertRegex(tag, r'^(v\d{4}\.\d{2}\.\d{2}(\.\d+)?|main-[0-9a-f]{8,40})$')
            self.assertTrue(krel.startswith(key + '.'), krel)

    def test_one_set_per_build(self):
        # a kernel's lines: the current build first, then earlier ones - of the same release with another configuration,
        # or of an earlier stable release (6.18.57 beside 6.18.58, with the same configuration). Each earlier set goes to
        # modules/<release>+<12 digits of CONFIG>/ in the tarball and to out/modules/KEY+<12 digits> in the build: both
        # names must be unique
        for key in {k[0] for k in kits()}:
            lines = [k for k in kits() if k[0] == key]
            self.assertEqual(len({(k[1], k[2][:12]) for k in lines}), len(lines), key)
            self.assertEqual(len({k[2][:12] for k in lines[1:]}), len(lines) - 1, key)
            self.assertEqual(sorted(lines, key=lambda k: tag_key(k[4]), reverse=True), lines, key)

    def test_build_takes_a_kit_only_with_its_hash(self):
        src = (TOP / 'kernel' / 'build.sh').read_text()
        self.assertIn('[ "$got" = "$KITSHA" ] ||', src)
        self.assertIn('releases/download/kits-$TAG/kit-$KEY.tar.xz', src)
        self.assertIn('case $v in "$KREL "*)', src)


if __name__ == '__main__':
    unittest.main()
