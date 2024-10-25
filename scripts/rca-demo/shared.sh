
# Define bash colors
# Reset
Color_Off='\033[0m'       # Text Reset

# Regular Colors
Black='\033[0;30m'        # Black
Red='\033[0;31m'          # Red
Green='\033[0;32m'        # Green
Yellow='\033[0;33m'       # Yellow
Blue='\033[0;34m'         # Blue
Purple='\033[0;35m'       # Purple
Cyan='\033[0;36m'         # Cyan
White='\033[0;37m'        # White

# Bold
BBlack='\033[1;30m'       # Black
BRed='\033[1;31m'         # Red
BGreen='\033[1;32m'       # Green
BYellow='\033[1;33m'      # Yellow
BBlue='\033[1;34m'        # Blue
BPurple='\033[1;35m'      # Purple
BCyan='\033[1;36m'        # Cyan
BWhite='\033[1;37m'       # White

title () {
	echo -e ${Cyan}"<[${BBlue} $1 ${Cyan}]>${Color_Off}"
}

warn () {
	echo -e ${Yellow}"<[${BYellow} $1 ${Yellow}]>${Color_Off}"
}

die () {
	echo -e "${BRed}ERROR: $1${Color_Off}"
	exit 1
}

autosource () {
	SCRIPTS_DIR=$(dirname "${BASH_SOURCE[0]}")
	LOAD_ENV_FILE_PATH=$SCRIPTS_DIR/.env

	if [ -n "${ENV_FILE_PATH}" ]; then
		LOAD_ENV_FILE_PATH=$ENV_FILE_PATH
	fi

	if [ -f $LOAD_ENV_FILE_PATH ]; then
		title "Sourcing environment variables from $LOAD_ENV_FILE_PATH"
		source $LOAD_ENV_FILE_PATH
	else
		warn "Environment variables file not found at $LOAD_ENV_FILE_PATH"
	fi
}