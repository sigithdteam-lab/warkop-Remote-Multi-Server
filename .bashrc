#autoload/start-up after login shell

if [[ -f ~/warkopv3.3.sh ]] && [[ -z "$WARKOP_RUN" ]]; th>
    export WARKOP_RUN=1
    ~/warkopv3.3.sh
    unset WARKOP_RUN
fi
