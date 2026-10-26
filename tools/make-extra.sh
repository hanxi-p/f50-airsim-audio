#!/bin/sh
# Build the release files of mu300-audio:
#   tools/make-extra.sh OUTDIR [TAG]      (TAG: vMAJOR.MINOR.PATCH, default v0.0.0-dev)
#   OUTDIR/mu300-audio.tar.gz    the extra mu300-audio (mu300-extra install mu300-audio --from): the call-audio stack
#                                with the drivers of every kernel of kernel/kits/kits.lock, modules/<release>/ (built by
#                                kernel/build.sh against the kernel's own build); an earlier build of a kernel's
#                                release beside it as modules/<release>+<first 12 digits of CONFIG>/. mu300-audio-dsp
#                                loads the set whose release and CONFIG fit the running kernel, whichever it is.
#   OUTDIR/VERSIONS              name, version, bytes, kernel releases, asset - TSV
#   OUTDIR/SHA256SUMS            both of the above, in sha256sum's format
# Inputs: out/modules/KEY/ (kernel/build.sh KEY) and out/bin/{pcmhost,ctlset,mu300-hfp} (src/*/build.sh, static
# arm64). MU300_AUDIO_FAKE=1 puts small stand-ins in place of both (tests/, no Docker).
# It unpacks into mu300-extra's directory for it ($DISK/extra/mu300-audio): files and directories only, owned by root,
# modes set here (programs and hooks 755, the rest 644), the same bytes from macOS and Linux for the same inputs.
# Besides its files: VERSION and release (= TAG), name (mu300-audio), requires (the mu300-linux release it needs:
# kernel/kits/requires), components, and manifest (the sha256 of every other file). No firmware.
set -eu
OUT=${1:?usage: tools/make-extra.sh OUTDIR [TAG]}
TAG=${2:-v0.0.0-dev}
case $TAG in v[0-9]*) ;; *) echo "TAG is vMAJOR.MINOR.PATCH" >&2; exit 2 ;; esac
TOP=$(cd "$(dirname "$0")/.." && pwd)
REQUIRES="mu300-linux $(sed -n 's/^\(v[0-9][0-9.]*\)$/\1/p' "$TOP/kernel/kits/requires" | head -1)"
[ "$REQUIRES" != "mu300-linux " ] || { echo "kernel/kits/requires names no mu300-linux release" >&2; exit 1; }
mkdir -p "$OUT"
OUT=$(cd "$OUT" && pwd)
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
FAKE=${MU300_AUDIO_FAKE:-}
KEYS=$(awk '!/^#/ && NF && !seen[$1]++ {print $1}' "$TOP/kernel/kits/kits.lock")

d=$tmp/x
mkdir -p "$d/bin" "$d/service/systemd" "$d/service/procd" "$d/etc" "$d/hooks" "$d/licence"
cp "$TOP/device/bin/mu300-audio-dsp" "$TOP/device/bin/mu300-voice" "$d/bin/"
for s in mu300-audio mu300-voice mu300-audio-reserve; do
    cp "$TOP/device/service/systemd/$s.service" "$d/service/systemd/"
    cp "$TOP/device/service/procd/$s" "$d/service/procd/"
done
cp "$TOP/device/etc/modprobe-mu300-audio.conf" "$TOP/device/etc/voice.conf.example" "$d/etc/"
cp "$TOP/hooks/link" "$TOP/hooks/unlink" "$d/hooks/"
cp "$TOP/LICENSE" "$d/licence/LICENSE"; cp "$TOP/kernel/COPYING" "$d/licence/COPYING"
if [ "$FAKE" = 1 ]; then
    for b in pcmhost ctlset mu300-hfp; do printf '#!/bin/sh\necho "%s (fake for tests)"\n' "$b" > "$d/bin/$b"; done
else
    for b in pcmhost ctlset mu300-hfp; do
        [ -s "$TOP/out/bin/$b" ] || { echo "no out/bin/$b (src/*/build.sh)" >&2; exit 1; }
        cp "$TOP/out/bin/$b" "$d/bin/"
    done
fi
printf 'mu300-audio %s\n' "$TAG" > "$d/components"
for KEY in $KEYS; do
    # every line of this kernel: the first one's set in modules/<release>/, an earlier build's beside it
    i=0
    awk -v k="$KEY" '$1 == k' "$TOP/kernel/kits/kits.lock" > "$tmp/lines"
    while read -r _ LREL LCONFIG _ LTAG; do
        i=$((i + 1))
        sub=$LREL src=$TOP/out/modules/$KEY
        [ "$i" = 1 ] || { sub=$LREL+$(printf %.12s "$LCONFIG"); src=$src+$(printf %.12s "$LCONFIG"); }
        mkdir -p "$d/modules/$sub"
        if [ "$FAKE" = 1 ]; then
            for m in audio_reserve audio_mem agdsp_access audio_sipc sprd_audcp_boot snd-soc-sprd-card; do
                printf 'vermagic=%s SMP\n' "$LREL" > "$d/modules/$sub/$m.ko"
            done
            printf 'KEY=%s\nKREL=%s\nCONFIG=%s\nTAG=%s\n' "$KEY" "$LREL" "$LCONFIG" "$LTAG" > "$d/modules/$sub/KERNEL"
        else
            grep -qx "KREL=$LREL" "$src/KERNEL" 2>/dev/null && grep -qx "CONFIG=$LCONFIG" "$src/KERNEL" ||
                { echo "${src#"$TOP"/} is not the kernel kits.lock names (kernel/build.sh $KEY)" >&2; exit 1; }
            cp "$src"/*.ko "$src/KERNEL" "$d/modules/$sub/"
        fi
        printf 'kernel %s (%s, mu300-linux %s)\n' "$KEY" "$LREL" "$LTAG" >> "$d/components"
    done < "$tmp/lines"
    rm -f "$tmp/lines"
done
echo "$TAG" > "$d/VERSION"; echo "$TAG" > "$d/release"; echo mu300-audio > "$d/name"; echo "$REQUIRES" > "$d/requires"

# python's tarfile, not tar: the same root-owned archive from macOS (bsdtar) and Linux (GNU tar), sorted, with fixed
# modes and times (SOURCE_DATE_EPOCH, else the last commit's time, else 0) and a gzip header without a time or name
python3 - "${SOURCE_DATE_EPOCH:-$(git -C "$TOP" log -1 --format=%ct 2>/dev/null || echo 0)}" "$d" "$OUT/mu300-audio.tar.gz" <<'PY'
import gzip, hashlib, io, os, sys, tarfile
mtime = int(sys.argv[1] or 0)
def executable(rel):
    return rel.startswith(('bin/', 'hooks/', 'service/procd/'))
def build(src, out):
    files = []
    for d, ds, fs in os.walk(src):
        ds.sort()
        for f in sorted(fs):
            files.append(os.path.relpath(os.path.join(d, f), src))
    with open(os.path.join(src, 'manifest'), 'w') as m:
        for rel in sorted(files):
            m.write('%s  ./%s\n' % (hashlib.sha256(open(os.path.join(src, rel), 'rb').read()).hexdigest(), rel))
    files.append('manifest')
    entries = set()
    for rel in files:
        parts = rel.split('/')
        for i in range(1, len(parts)):
            entries.add(('/'.join(parts[:i]), True))
        entries.add((rel, False))
    buf = io.BytesIO()
    with tarfile.open(fileobj=buf, mode='w', format=tarfile.GNU_FORMAT) as t:
        for rel, isdir in sorted(entries):
            ti = tarfile.TarInfo('./' + rel)
            ti.uid = ti.gid = 0
            ti.uname = ti.gname = 'root'
            ti.mtime = mtime
            if isdir:
                ti.type, ti.mode = tarfile.DIRTYPE, 0o755
                t.addfile(ti)
            else:
                data = open(os.path.join(src, rel), 'rb').read()
                ti.size, ti.mode = len(data), 0o755 if executable(rel) else 0o644
                t.addfile(ti, io.BytesIO(data))
    with open(out, 'wb') as f, gzip.GzipFile(filename='', mode='wb', fileobj=f, mtime=0, compresslevel=9) as g:
        g.write(buf.getvalue())
args = sys.argv[2:]
for i in range(0, len(args), 2):
    build(args[i], args[i + 1])
PY
rm -f "$OUT"/mu300-audio-*.tar.gz
( cd "$OUT"
  f=mu300-audio.tar.gz
  printf 'mu300-audio\t%s\t%s\t%s\t%s\n' "$TAG" "$(wc -c < "$f" | tr -d ' ')" \
      "$(awk '!/^#/ && NF {print $2}' "$TOP/kernel/kits/kits.lock" | LC_ALL=C sort -u | tr '\n' ' ' | sed 's/ $//')" "$f" > VERSIONS
  for f in mu300-audio.tar.gz VERSIONS; do
      s=$(shasum -a 256 "$f" 2>/dev/null || sha256sum "$f"); printf '%s  %s\n' "${s%% *}" "$f"
  done > SHA256SUMS )
echo "mu300-audio.tar.gz ($TAG): $(du -h "$OUT/mu300-audio.tar.gz" | cut -f1)"
echo "SHA256SUMS: $OUT/SHA256SUMS"
