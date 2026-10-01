control_expect 'retired setting refuses'
control_replace scripts/lib/common.sh 1 \
    'if [[ -n "${LINEAR_CACHE_ROOT+set}" ]]; then' \
    'if [[ -n "${LINEAR_CACHE_ROOT+set}" && -z "${LINEAR_CACHE_ROOT+set}" ]]; then'
