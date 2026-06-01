#!/usr/bin/env bash
# Build and package PiliPlus for Linux arm64 on ubuntu-24.04-arm (GitHub Actions).
set -euo pipefail

version_name="$(grep -E '^\s*version:' pubspec.yaml | head -1 | sed -E 's/^\s*version:\s*([0-9.]+).*/\1/')"
version_code="$(git rev-list --count HEAD)"
commit_hash="$(git rev-parse HEAD)"
build_time="$(date +%s)"
full_version="${version_name}+${version_code}"

sed -i "s/^version:.*/version: ${full_version}/" pubspec.yaml
printf '{"pili.name":"%s","pili.code":%s,"pili.hash":"%s","pili.time":%s}\n' \
  "$version_name" "$version_code" "$commit_hash" "$build_time" > pili_release.json
echo "version=${full_version}" >> "${GITHUB_ENV}"

flutter config --enable-linux-desktop
flutter pub get
flutter build linux --release -v --pub --dart-define-from-file=pili_release.json

bundle_dir="build/linux/arm64/release/bundle"
if [[ ! -d "${bundle_dir}" ]]; then
  echo "ERROR: bundle not found at ${bundle_dir}"
  ls -la build/linux || true
  exit 1
fi

tar -zcvf "PiliPlus_linux_${full_version}_arm64.tar.gz" -C "${bundle_dir}" .

pkg_root="PiliPlus_linux_${full_version}_arm64"
rm -rf "${pkg_root}"
mkdir -p "${pkg_root}/opt/PiliPlus" \
         "${pkg_root}/usr/share/applications" \
         "${pkg_root}/usr/share/icons/hicolor/512x512/apps"

cp -a "${bundle_dir}/." "${pkg_root}/opt/PiliPlus/"
cp -a assets/linux/DEBIAN "${pkg_root}/DEBIAN"
cp assets/linux/com.example.piliplus.desktop "${pkg_root}/usr/share/applications/"
cp assets/images/logo/logo.png "${pkg_root}/usr/share/icons/hicolor/512x512/apps/piliplus.png"

sed -i "2s/version_need_change/${full_version}/" "${pkg_root}/DEBIAN/control"
sed -i 's/^Architecture: amd64/Architecture: arm64/' "${pkg_root}/DEBIAN/control"
sed -i 's/libgtk-3-0t64/libgtk-3-0/' "${pkg_root}/DEBIAN/control"
sed -i 's/libmpv2/libmpv1 | libmpv2/' "${pkg_root}/DEBIAN/control"

pushd "${pkg_root}" >/dev/null
size_kb="$(du -s -b --apparent-size . | awk '{print int($1)}')"
size_kb="$(du -s -b --apparent-size DEBIAN | awk -v t="$size_kb" '{print t - int($1)}')"
size_kb="$(awk -v s="$size_kb" 'BEGIN { printf "%d", int(s/1024 + 0.999) }')"
sed -i "9s/size_need_change/${size_kb}/" DEBIAN/control
: > DEBIAN/md5sums
md5sum opt/PiliPlus/piliplus >> DEBIAN/md5sums
find opt/PiliPlus/lib -type f -exec md5sum {} + >> DEBIAN/md5sums 2>/dev/null || true
md5sum opt/PiliPlus/data/icudtl.dat >> DEBIAN/md5sums
chmod 0644 DEBIAN/control DEBIAN/md5sums
chmod 0755 DEBIAN/postinst DEBIAN/postrm DEBIAN/prerm
popd >/dev/null

dpkg-deb --build --root-owner-group "${pkg_root}"
echo "Built ${pkg_root}.deb"
