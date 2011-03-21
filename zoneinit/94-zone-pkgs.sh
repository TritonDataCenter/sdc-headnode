set -o xtrace
set -o errtrace

# This allows us to tell SMF that an error was fatal
. /lib/svc/share/smf_include.sh
trap "exit $SMF_EXIT_ERR_FATAL" ERR

echo "94 installing local pkgs"

if [[ -d "/root/pkgsrc" && -f "/root/pkgsrc/order" ]]; then
    for pkg in `cat /root/pkgsrc/order | xargs`; do
        echo "installing ${pkg}"
        pkg_info ${pkg} >/dev/null 2>&1 || pkg_add -f /root/pkgsrc/${pkg}
    done
else
    echo "no packages to install."
fi
