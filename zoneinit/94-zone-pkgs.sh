echo "94 installing local pkgs"

if [[ -d "/root/pkgsrc" && -f "/root/pkgsrc/order" ]]; then
    for pkg in `cat /root/pkgsrc/order | xargs`; do
        echo "installing ${pkg}"
        pkg_add -f /root/pkgsrc/${pkg}.tgz
    done
else
    echo "no packages to install."
fi
