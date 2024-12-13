#!/bin/bash

# Функция для отображения цветного прогресс-бара
show_progress() {
    local progress=$1
    local width=50
    local fill=$((progress * width / 100))
    local empty=$((width - fill))

    local color_reset="\e[0m"
    local color_fill="\e[42m"
    local color_empty="\e[41m"

    printf "\r["
    printf "${color_fill}%*s${color_reset}" "$fill" ""
    printf "${color_empty}%*s${color_reset}" "$empty" ""
    printf "] %d%%" "$progress"
}

# Функция для проверки имени пользователя
validate_username() {
    local username=$1
    if [[ "$username" =~ ^[a-zA-Z0-9_]+$ ]]; then
        return 0
    else
        echo "Неверное имя пользователя. Оно должно содержать только буквы, цифры и подчеркивания."
        return 1
    fi
}

# Функция для проверки наличия логов
check_logs() {
    if ! ls /var/log/*.log 1>/dev/null 2>&1 || ! grep -q 'auth.log' /var/log/*.log; then
        return 1
    fi
    return 0
}

# Функция для выполнения обновлений
perform_updates() {
    echo "Обновление и установка пакетов..."
    apt-get update -y >/dev/null 2>&1
    show_progress 20
    apt-get upgrade -y >/dev/null 2>&1
    show_progress 50
    apt-get install -y sudo ufw fail2ban >/dev/null 2>&1
    show_progress 90
    show_progress 100
    echo -e "\nНастройка завершена!"
}

# Функция для создания нового пользователя
create_new_user() {
    local username password password_confirm
    while true; do
        read -p "Введите имя нового пользователя (без пробелов и специальных символов): " username
        validate_username "$username" && break
    done

    while true; do
        read -s -p "Введите пароль для нового пользователя: " password
        echo
        read -s -p "Повторите пароль: " password_confirm
        echo
        if [[ "$password" == "$password_confirm" && -n "$password" ]]; then
            break
        else
            echo "Пароли не совпадают или пусты. Попробуйте снова."
        fi
    done

    useradd -m -s /bin/bash "$username"
    echo "$username:$password" | chpasswd
    usermod -aG sudo "$username"
    echo -e "\nПользователь $username успешно создан и добавлен в группу sudo."
}

# Функция для изменения порта SSH
change_ssh_port() {
    local ssh_port
    while true; do
        read -p "Введите новый порт SSH (рекомендуется диапазон от 1024 до 65535): " ssh_port
        if [[ "$ssh_port" =~ ^[0-9]+$ ]] && ((ssh_port >= 1024 && ssh_port <= 65535)); then
            break
        else
            echo "Пожалуйста, введите корректный порт в диапазоне от 1024 до 65535."
        fi
    done

    sed -i "s/^#Port 22/Port $ssh_port/" /etc/ssh/sshd_config
    systemctl restart ssh
    echo -e "\nПорт SSH успешно изменен на $ssh_port."
}

# Функция для настройки фаервола
configure_firewall() {
    local ssh_port=$1
    ufw allow "$ssh_port"/tcp >/dev/null 2>&1
    show_progress 20
    ufw allow http >/dev/null 2>&1
    ufw allow https >/dev/null 2>&1
    show_progress 50
    ufw default deny incoming >/dev/null 2>&1
    ufw default allow outgoing >/dev/null 2>&1
    show_progress 70
    ufw --force enable >/dev/null 2>&1
    show_progress 100
    echo -e "\nФаервол успешно настроен!"
}

# Функция для запрета входа по SSH для root
disable_root_ssh() {
    read -p "Хотите запретить вход по SSH для root-пользователя? (да/нет): " disable_root_ssh
    if [[ "$disable_root_ssh" =~ ^(да|y|yes)$ ]]; then
        sed -i '/^#*PermitRootLogin/s/^#*\(.*\)/PermitRootLogin no/' /etc/ssh/sshd_config
        systemctl restart ssh
        echo -e "\nВход по SSH для root-пользователя успешно запрещен."
    else
        echo -e "\nВход по SSH для root-пользователя оставлен включенным."
    fi
}

# Функция для настройки fail2ban
install_fail2ban() {
    read -p "Хотите установить защиту от брутфорса с помощью fail2ban? (да/нет): " install_fail2ban
    if [[ "$install_fail2ban" =~ ^(да|y|yes)$ ]]; then
        echo -e "\nНастройка fail2ban..."
        read -p "Введите количество неудачных попыток входа до блокировки: " max_attempts
        read -p "Введите время блокировки в секундах: " bantime
        read -p "Введите временной интервал (в секундах) для подсчета попыток: " findtime

        cat <<EOL > /etc/fail2ban/jail.d/ssh.local
[sshd]
enabled = true
port = $ssh_port
logpath = /var/log/auth.log
maxretry = $max_attempts
bantime = $bantime
findtime = $findtime
EOL

        systemctl restart fail2ban
        echo -e "\nЗащита от брутфорса с помощью fail2ban настроена и активирована."
    else
        echo -e "\nЗащита от брутфорса с помощью fail2ban не будет установлена."
    fi
}

# Основной блок выполнения
perform_updates

if ! check_logs; then
    echo -e "\nЛоги не найдены. Устанавливаем rsyslog..."
    apt-get install -y rsyslog >/dev/null 2>&1
    systemctl restart rsyslog
    echo -e "\nRsyslog установлен и перезапущен."
else
    echo -e "\nЛоги найдены, продолжаем настройку Fail2Ban."
fi

# Запрос на создание нового пользователя
read -p "Хотите создать нового пользователя для входа в систему вместо root? (да/нет): " create_new_user
create_new_user=$(echo "$create_new_user" | tr '[:upper:]' '[:lower:]' | tr -s ' ')

if [[ "$create_new_user" =~ ^(да|y|yes)$ ]]; then
    create_new_user
else
    echo -e "\nОставляем root-пользователя для входа в систему."
fi

# Настройка порта для SSH
change_ssh_port

# Настройка фаервола с UFW
configure_firewall "$ssh_port"

# Запретить root доступ по SSH
disable_root_ssh

# Установка защиты от брутфорса с fail2ban
install_fail2ban
