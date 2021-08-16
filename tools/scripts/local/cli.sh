#!/bin/bash

#?###################################################################################################
#?                                                                                                  #
#?                                      Output Helper Methods                                       #
#?                                                                                                  #
#?###################################################################################################

# ! little helpers for terminal print control and key input
select_option (){
  ESC=$(printf '%b' "\033")

  cursor_blink_on() {
    printf '%s' "$ESC[?25h"
  }

  cursor_blink_off() {
    printf '%s' "$ESC[?25l"
  }

  cursor_to() {
    printf '%s' "$ESC[$1;${2:-1}H"
  }

  print_option() {
    printf '   %s ' "$1"
  }

  print_selected() {
    printf '  %s' "$ESC[7m $1 $ESC[27m"
  }

  get_cursor_row() {
    IFS=';' read -sdR -p $'\E[6n' ROW COL; printf '%s' ${ROW#*[}
  }

  key_input() {
    read -s -n3 key 2>/dev/null >&2
    if [[ $key = $ESC[A ]]; then
      echo up
    fi
    if [[ $key = $ESC[B ]]; then
      echo down
    fi
    if [[ $key = ""  ]]; then
      echo enter
    fi
  }

   # initially print empty new lines (scroll down if at bottom of screen)
   for opt; do
     printf "\n"
   done

   # determine current screen position for overwriting the options
   local lastrow=$(get_cursor_row)
   local startrow=$(($lastrow - $#))

   # ensure cursor and input echoing back on upon a ctrl+c during read -s
   trap "cursor_blink_on; stty echo; printf '\n'; exit" 2
   cursor_blink_off

   local selected=0
   while true; do
     # print options by overwriting the last lines
     local idx=0
     for opt; do
       cursor_to $((startrow + idx))
       if [[ $idx == $selected ]]; then
         print_selected "$opt"
       else
         print_option "$opt"
       fi
       ((idx++))
     done

     # user key control
     case $(key_input) in
       enter) break;;
       up)    ((selected--));
         if (( $selected < 0 )); then selected=$(($# - 1)); fi;;
         down)  ((selected++));
           if (( selected > $# )); then selected=0; fi;;
         esac
       done

       # cursor position back to normal
       cursor_to $lastrow
       printf "\n"
       cursor_blink_on

       return "$selected"
}

#!###################################################################################################
#!                                                                                                  #
#!                                       Script Start                                               #
#!                                                                                                  #
#!###################################################################################################

# Print Instructions
printf '\n> %s\n\n' "$(tput setaf 3)Please Choose your Shell$(tput sgr 0)":

# Options
options=("Bash" "Zsh" "IDK")

select_option "${options[@]}"
choice=$?

index=$choice
value=${options[$choice]}

case $value in 
  Bash)  ## User selected Bash
   shellrc=".bashrc"
   ;;
  Zsh) ## User Selected zsh
   shellrc=".zshrc"
   ;;
  IDK) ## User doesn't know
   shellrc=".bashrc"
   ;;
esac

####################################################################################################

# ? Remove Prexisting CLI Script
sed -n -i '1,/# StackHelper CLI START/p;/# StackHelper CLI END/,$p' $HOME/$shellrc
sed -i '/# StackHelper CLI START/d' $HOME/$shellrc
sed -i '/# StackHelper CLI END/d' $HOME/$shellrc

####################################################################################################

# ? Echo the CLI in the user's .shellrc
echo '
# StackHelper CLI START
# This function serves to integrate
# the dependency-less CLI for 
# Interactive Events Platform

shelper() {
    if [[ $@ == "build" ]]; then
        command docker exec -i client npm run build
    elif [[ $@ == "serve" ]]; then
        command docker-compose run --rm -p "8081:8081" npm run serve
    elif [[ $@ == "install client" || $@ == "i client" ]]; then
        command docker exec -i client npm install
    elif [[ $@ == "install api" || $@ == "i api" ]]; then
        command docker exec -i backend composer install &&
        command docker exec -i backend composer dump-autoload &&
        command docker exec -i backend php artisan key:generate &&
        command docker exec -i backend php artisan migrate:fresh
    elif [[ $@ == "api migrate" ]]; then
        command docker exec -i backend php artisan migrate
    elif [[ $@ == "api seed" ]]; then
        command docker exec -i backend php artisan db:seed
    elif [[ $@ == "api ms" ]]; then
        command docker exec -i backend php artisan migrate:fresh --seed
    elif [[ $@ == "api refresh" ]]; then
        command docker exec -i backend composer dump-autoload &&
        command docker exec -i backend php artisan migrate:fresh --seed
    elif [[ $@ == "stack refresh" || $@ == "stack r" ]]; then
        command docker-compose down && command docker-compose up -d
    elif [[ $@ == "-h" || $@ == "--help" ]]; then
        echo " 
$(tput setaf 3)Stack Helper CLI$(tput sgr 0)

$(tput setaf 3)Usage:$(tput sgr 0)
    shelper [options] [arguments]

$(tput setaf 3)Options:$(tput sgr 0)

-h, --help          Displays this help page

$(tput setaf 3)Arguments:$(tput sgr 0)
    $(tput setaf 2)build$(tput sgr 0)                 Builds the Front-end
    $(tput setaf 1)serve$(tput sgr 0)                 Serves the front-end through port $(tput setaf 5)8081$(tput sgr 0)
    $(tput setaf 3)install client$(tput sgr 0)        Installs the npm Dependencies Shorthand -> $(tput setaf 5)i ui$(tput sgr 0)
    $(tput setaf 3)install api$(tput sgr 0)           Installs Laravel Dependencies, Generate Keys & Migrate DB Shorthand -> $(tput setaf 5)i api$(tput sgr 0)
    $(tput setaf 4)api migrate$(tput sgr 0)           Pushes Laravel Migrations to DB
    $(tput setaf 4)api seed$(tput sgr 0)              Seed the Database
    $(tput setaf 4)api ms$(tput sgr 0)                Migrate & Seed
    $(tput setaf 4)api refresh$(tput sgr 0)           Composer dump-autoload, Migrate & Seed
    $(tput setaf 6)stack refresh$(tput sgr 0)         Refresh the docker stack down/up Shorthand -> $(tput setaf 5)stack r$(tput sgr 0)
"
    else
        echo "
$(tput setaf 1)Please Input a Valid Argument$(tput sgr 0)
OR 
Check the Proper Syntax with
$(tput setaf 3)$ shelper -h$(tput sgr 0)
"
    fi
}

# For Tab-Completion (Basic/Rudimentary)
_shelper_completions()
{
  COMPREPLY+=("build")
  COMPREPLY+=("serve")
  COMPREPLY+=("install")
  COMPREPLY+=("api")
  COMPREPLY+=("stack")
}

complete -F _shelper_completions shelper
# StackHelper CLI END
' >> $HOME/$shellrc