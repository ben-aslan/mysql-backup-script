#!/bin/bash

# Bot token
# Get telegram bot token
while [[ -z "$tk" ]]; do
    echo "Bot token: "
    read -r tk
    if [[ $tk == $'\0' ]]; then
        echo "Invalid input. Token cannot be empty."
        unset tk
    fi
done

# Chat id
# Get chat id
while [[ -z "$chatid" ]]; do
    echo "Chat id: "
    read -r chatid
    if [[ $chatid == $'\0' ]]; then
        echo "Invalid input. Chat id cannot be empty."
        unset chatid
    elif [[ ! $chatid =~ ^\-?[0-9]+$ ]]; then
        echo "${chatid} is not a number."
        unset chatid
    fi
done

# Caption
# Get caption
echo "Caption (for example, your domain, to identify the database file more easily): "
read -r caption

# host
# Get host
while [[ -z "$host" ]]; do
    echo "Host: (default=127.0.0.1)"
    read -r host
    if [[ $host == $'\0' ]]; then
        host="127.0.0.1"
    fi
done

# port
# Get port
while [[ -z "$port" ]]; do
    echo "Port: (default=3306)"
    read -r port
    if [[ $port == $'\0' ]]; then
        port="3306"
    fi
done

# mysqluser
# Get mysql user
while [[ -z "$mysqluser" ]]; do
    echo "Mysql user: "
    read -r mysqluser
    if [[ $mysqluser == $'\0' ]]; then
        echo "Invalid input. mysql user cannot be empty."
        unset mysqluser
    fi
done

# mysqlpass
# Get mysql password
while [[ -z "$mysqlpass" ]]; do
    echo "Mysql password: "
    read -r mysqlpass
    if [[ $mysqlpass == $'\0' ]]; then
        echo "Invalid input. mysql password cannot be empty."
        unset mysqlpass
    fi
done

# Cronjob
# Get cronjob
while true; do
    echo "Cronjob (minutes and hours) (e.g : 30 6 or 0 12) : "
    read -r minute hour
    if [[ $minute == 0 ]] && [[ $hour == 0 ]]; then
        cron_time="* * * * *"
        break
    elif [[ $minute == 0 ]] && [[ $hour =~ ^[0-9]+$ ]] && [[ $hour -lt 24 ]]; then
        cron_time="0 */${hour} * * *"
        break
    elif [[ $hour == 0 ]] && [[ $minute =~ ^[0-9]+$ ]] && [[ $minute -lt 60 ]]; then
        cron_time="*/${minute} * * * *"
        break
    elif [[ $minute =~ ^[0-9]+$ ]] && [[ $hour =~ ^[0-9]+$ ]] && [[ $hour -lt 24 ]] && [[ $minute -lt 60 ]]; then
        cron_time="*/${minute} */${hour} * * *"
        break
    else
        echo "Invalid input, please enter a valid cronjob format (minutes and hours, e.g: 0 6 or 30 12)"
    fi
done

while [[ -z "$crontabs" ]]; do
    echo "Would you like the previous crontabs to be cleared? [y/n] : "
    read -r crontabs
    if [[ $crontabs == $'\0' ]]; then
        echo "Invalid input. Please choose y or n."
        unset crontabs
    elif [[ ! $crontabs =~ ^[yn]$ ]]; then
        echo "${crontabs} is not a valid option. Please choose y or n."
        unset crontabs
    fi
done

if [[ "$crontabs" == "y" ]]; then
# remove cronjobs
sudo crontab -l | grep -vE '/opt/mysql-backup/ac-backup.+\.sh' | crontab -
fi

mkdir /opt/mysql-backup

# create mysql-backup.sh
    cat > "/opt/mysql-backup/mysql-backup.sh" <<EOL
#!/bin/bash

USER="$mysqluser"
PASSWORD="$mysqlpass"
HOST="$host"
PORT="$port"


databases=\$(mysql -h \$HOST -P \$PORT --user=\$USER --password=\$PASSWORD -e "SHOW DATABASES;" | tr -d "| " | grep -v Database)

for db in \$databases; do
    if [[ "\$db" != "information_schema" ]] && [[ "\$db" != "mysql" ]] && [[ "\$db" != "performance_schema" ]] && [[ "\$db" != "sys" ]] ; then
        echo "Dumping database: \$db"
                mysqldump -h \$HOST -P \$PORT --force --opt --user=\$USER --password=\$PASSWORD --databases \$db > /opt/mysql-backup/db-backup/\$db.sql

    fi
done

EOL
chmod +x /opt/mysql-backup/mysql-backup.sh

ZIP=$(cat <<EOF
bash -c "/opt/mysql-backup/mysql-backup.sh"
zip -r /opt/mysql-backup/ac-backup-m.zip /opt/mysql-backup/db-backup/*
rm -rf /opt/mysql-backup/db-backup/*
EOF
)


ben_aslan="mysql backup"

trim() {
    # remove leading and trailing whitespace/lines
    local var="$*"
    # remove leading whitespace characters
    var="${var#"${var%%[![:space:]]*}"}"
    # remove trailing whitespace characters
    var="${var%"${var##*[![:space:]]}"}"
    echo -n "$var"
}

IP=$(ip route get 1 | sed -n 's/^.*src \([0-9.]*\) .*$/\1/p')
caption="${caption}\n\n${ben_aslan}\n<code>${IP}</code>\nCreated by @ben-aslan - https://github.com/ben-aslan/mysql-backup"
comment=$(echo -e "$caption" | sed 's/<code>//g;s/<\/code>//g')
comment=$(trim "$comment")

# install zip
sudo apt install zip -y

# send backup to telegram
cat > "/opt/mysql-backup/mysql-backup.sh" <<EOL
rm -rf /opt/mysql-backup/mysql-backup.zip
$ZIP
echo -e "$comment" | zip -z /opt/mysql-backup/mysql-backup.zip
curl -F chat_id="${chatid}" -F caption=\$'${caption}' -F parse_mode="HTML" -F document=@"/opt/mysql-backup/mysql-backup.zip" https://api.telegram.org/bot${tk}/sendDocument
EOL


# Add cronjob
{ crontab -l -u root; echo "${cron_time} /bin/bash /opt/mysql-backup/mysql-backup.sh >/dev/null 2>&1"; } | crontab -u root -

# run the script
bash "/opt/mysql-backup/mysql-backup.sh"

# Done
echo -e "\nDone\n"