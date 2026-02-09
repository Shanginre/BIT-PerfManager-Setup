#!/bin/bash

# Параметры скрипта
SERVER_TYPE=""
ONEC_VERSION=""
ONEC_CLUSTER_PORT=""
ONEC_RAS_PORT=""
ONEC_CLUSTER_FOLDER=""
SHARE_USER=""

# Функция для вывода справки
show_usage() {
    echo "Использование: $0 [параметры]"
    echo "Параметры:"
    echo "  --server-type=TYPE       Тип сервера (1C, PostgreSQL, 1C_PostgreSQL, other)"
    echo "      TYPE:"
    echo "          1C             - на сервере работает только служба сервера 1С"
    echo "          PostgreSQL     - на сервере работает только служба PostgreSQL"
    echo "          1C_PostgreSQL  - на сервере работает служба 1C и служба PostgreSQL"
    echo "          other          - на сервере не работают служба 1С и службы СУБД"        
    echo "  --1c-version=VERSION     Версия платформы 1С (например: 8.3.20.1800)"
    echo "  --1c-cluster-port=PORT   Порт кластера 1С (по умолчанию: 1540)"
    echo "  --1c-ras-port=PORT       Порт RAS 1С (по умолчанию: 1545)"
    echo "  --1c-cluster-folder=PATH Путь к директории кластера 1С"
    echo "  --share-user=USER        Пользователь для доступа к сетевым папкам"
    echo ""

}

# Парсинг аргументов командной строки
parse_arguments() {
    for arg in "$@"; do
        case $arg in
            --server-type=*)
                SERVER_TYPE="${arg#*=}"
                shift
                ;;
            --1c-version=*)
                ONEC_VERSION="${arg#*=}"
                shift
                ;;
            --1c-cluster-port=*)
                ONEC_CLUSTER_PORT="${arg#*=}"
                shift
                ;;
            --1c-ras-port=*)
                ONEC_RAS_PORT="${arg#*=}"
                shift
                ;;
            --1c-cluster-folder=*)
                ONEC_CLUSTER_FOLDER="${arg#*=}"
                shift
                ;;
            --share-user=*)
                SHARE_USER="${arg#*=}"
                shift
                ;;
            --help)
                show_usage
                exit 0
                ;;
            *)
                echo "Неизвестный параметр: $arg"
                show_usage
                exit 1
                ;;
        esac
    done
}

# Проверка входных параметров
check_parameters() {
    echo "-------------------------------------------------------------------------------------------------"
    echo "Проверяем корректность заполнения входных параметров скрипта"
    echo ""

    if [ -z "$SERVER_TYPE" ]; then
        echo "Не задан тип сервера. Укажите в параметрах запуска скрипта: --server-type=xxxx"
        echo ""
        echo "Значения типов сервера могут быть следующие:"
        echo "  1C              - на сервере работает только служба сервера 1С"
        echo "  PostgreSQL      - на сервере работает только служба PostgreSQL"
        echo "  1C_PostgreSQL   - на сервере работает служба 1C и служба PostgreSQL"
        echo "  other           - на сервере не работают служба 1С и службы СУБД"
        exit 1
    fi

    # Нормализация типа сервера
    if [[ "$SERVER_TYPE" == *"1С"* ]] || [[ "$SERVER_TYPE" == *"1C"* ]]; then
        SERVER_TYPE="1C"
    fi

    if [[ "$SERVER_TYPE" == *"1C"* ]] && [ -z "$ONEC_VERSION" ]; then
        echo "ERROR: не задана версия платформы кластера 1С. Укажите в параметрах запуска скрипта: --1c-version=8.x.xx.xxxx"
        exit 1
    fi

    if [[ "$SERVER_TYPE" == *"1C"* ]] && [ -z "$ONEC_CLUSTER_PORT" ]; then
        ONEC_CLUSTER_PORT="1540"
        echo "INFO: задан стандартный порт 1540 кластера 1С. Если требуется указать другой порт, укажите в параметрах запуска скрипта: --1c-cluster-port=xxxx"
    fi

    if [[ "$SERVER_TYPE" == *"1C"* ]] && [ "$ONEC_CLUSTER_PORT" != "1540" ] && [ -z "$ONEC_RAS_PORT" ]; then
        echo "ERROR: для кластера 1С задан нестандартный порт. Укажите порт агента RAS (по умолчанию 1545), к которому будет обращаться система мониторинга: --1c-cluster-port=xxxx"
        exit 1
    fi

    if [[ "$SERVER_TYPE" == *"1C"* ]] && [ "$ONEC_CLUSTER_PORT" = "1540" ] && [ -z "$ONEC_RAS_PORT" ]; then
        ONEC_RAS_PORT="1545"
        echo "INFO: задан стандартный порт 1545 агента RAS. Если требуется указать другой порт, укажите в параметрах запуска скрипта: --1c-ras-port=xxxx"
    fi

    if [[ "$SERVER_TYPE" == *"1C"* ]] && [ -z "$ONEC_CLUSTER_FOLDER" ]; then
        ONEC_CLUSTER_FOLDER="/home/usr1cv8/.1cv8/1C/1cv8"
        echo "INFO: задан стандартный путь директории кластера /home/usr1cv8/.1cv8/1C/1cv8. Если требуется указать другой путь, укажите в параметрах запуска скрипта: --1c-cluster-folder=xxxx"
    fi

    if [ -z "$SHARE_USER" ]; then
        echo "ERROR: не задано имя пользователя, для которого будут открыты сетевые папки с логами. Укажите в параметрах запуска скрипта: --share-user=xxxx"
        exit 1
    fi
}

# Настройка сбора метрик
setup_logging() {
    echo "-------------------------------------------------------------------------------------------------"
    echo "Настраиваем сбор логов"
    echo ""
    echo "Создаем папки для сбора логов мониторинга"
    
    # Создаем папки
    script_directory="/opt/bit"
    if [ ! -d "$script_directory" ]; then
        mkdir -p "$script_directory";
        chmod 777 "$script_directory";
    fi

    root_logs_directory="/var/log/bit_monitoring"
    if [ ! -d "$root_logs_directory" ]; then
        mkdir -p "$root_logs_directory";
        chmod 777 "$root_logs_directory";
    fi

    server_counters_directory="/var/log/bit_monitoring/server_counters_logs"
    if [ ! -d "$server_counters_directory" ]; then
        mkdir -p "$server_counters_directory";
        chmod 777 "$server_counters_directory";
    fi

    tech_logs_directory="/var/log/bit_monitoring/1C_tech_logs"
    if [ ! -d "$tech_logs_directory" ]; then
        mkdir -p "$tech_logs_directory";
        chmod 777 "$tech_logs_directory";
    fi

    cluster_folders_sizes_directory="/var/log/bit_monitoring/cluster_folders_sizes_logs"
    if [ ! -d "$cluster_folders_sizes_directory" ]; then
        mkdir -p "$cluster_folders_sizes_directory";
        chmod 777 "$cluster_folders_sizes_directory";
    fi

    # Включаем логирование счетчиков сервера
    if [ -f "collect_server_counters.sh" ]; then
        echo "Копируем в /opt/bit файл collect_server_counters.sh для сбора счетчиков сервера"

        cp collect_server_counters.sh /opt/bit
        chmod 777 /opt/bit/collect_server_counters.sh
        chmod +x /opt/bit/collect_server_counters.sh

        echo "Создаем cron задание для ежечасного перезапуска скрипта collect_server_counters.sh"
        cat > /etc/cron.hourly/collect_server_counters << EOF
#!/bin/bash
/opt/bit/collect_server_counters.sh
EOF
        chmod +x /etc/cron.hourly/collect_server_counters
    else
        echo "ERROR: не найден файл collect_server_counters.sh"
        exit 1
    fi
    
    # Включаем сбор логов тех. журнала
    if [[ "$SERVER_TYPE" == *"1C"* ]]; then
        echo "Копируем в /opt/1cv8/conf файл logcfg.xml для включения сбора логов тех. журнала 1С"
        
        if [ -f "logcfg.xml" ]; then
            cp logcfg.xml /opt/1cv8/conf
            chmod 777 /opt/1cv8/conf/logcfg.xml
        else
            echo "ERROR: не найден файл logcfg.xml"
            exit 1
        fi
    fi

    # Включаем логирование размеров папок кластера
    if [[ "$SERVER_TYPE" == *"1C"* ]]; then
        echo "-------------------------------------------------------------------------------------------------"
        echo "Настраиваем мониторинг размеров папок кластера 1С"
        echo ""

        echo "Создаем скрипт save_cluster_folders_size.sh для сбора размеров папок"
        cat > /opt/bit/save_cluster_folders_size.sh << EOF
#!/bin/bash
archiving_date=\$(date +'%y%m%d%H')
du --apparent-size --max-depth=3 "${ONEC_CLUSTER_FOLDER}" > /var/log/bit_monitoring/cluster_folders_sizes_logs/ClusterSizeLogs_\${archiving_date}.txt
EOF
        
        chmod +x /opt/bit/save_cluster_folders_size.sh
        
        echo "Создаем cron задание для ежечасного выполнения скрипта save_cluster_folders_size.sh"
        cat > /etc/cron.hourly/bit_cluster_folders << EOF
#!/bin/bash
/opt/bit/save_cluster_folders_size.sh
EOF
        chmod +x /etc/cron.hourly/bit_cluster_folders
    fi
}

# Настройка службы RAS для 1С
setup_ras_service() {
    
    if [[ "$SERVER_TYPE" == *"1C"* ]]; then
        # Настройка сбора метрик 1С
        echo "-------------------------------------------------------------------------------------------------"
        echo "Настраиваем службу RAS"
        echo ""

        # Проверяем наличие утилиты ras
        if command -v ras &> /dev/null; then
            echo "RAS обнаружен, создание новой службы не требуется"
        else
            cat > /etc/systemd/system/ras.service << EOF
[Unit]
Description=1C:Enterprise 8.3 Remote Agent Server
After=syslog.target
After=network.target

[Service]
Type=forking
User=usr1cv8
Group=grp1cv8
OOMScoreAdjust=-100
ExecStart=/opt/1cv8/x86_64/${ONEC_VERSION}/ras cluster --daemon -p ${ONEC_RAS_PORT} ${HOSTNAME}:${ONEC_CLUSTER_PORT}
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
        
            # Перезагружаем systemd и включаем службу
            systemctl daemon-reload
            systemctl enable ras.service
            systemctl start ras.service
            
        if command -v ras &> /dev/null; then
                echo "Служба RAS настроена и запущена на порту ${ONEC_RAS_PORT}"
        else 
                echo "ERROR: ошибка установки службы RAS. Необходимо настроить запуск RAS вручную"
        fi
        fi
    fi
}

# Настройка общего доступа к логам
setup_share_access() {
    echo "-------------------------------------------------------------------------------------------------"
    echo "Настраиваем сетевой доступ к логам"
    echo ""
    
    if command -v samba &> /dev/null; then
        echo "Настраиваем Samba shares..."
        setup_samba_shares
    else
        echo "ERROR: Samba не установлен. Необходимо настроить сетевой доступ к папкам вручную."
    fi
}

# Настройка Samba shares
setup_samba_shares() {
    if command -v samba &> /dev/null; then
        # Конфигурация Samba
        cat >> /etc/samba/smb.conf << EOF

[BIT_server_counters_logs]
    path = /var/log/bit_monitoring/server_counters_logs
    read only = no
    browsable = yes
    public = yes
    writable = yes
    read only = no
    guest ok = yes
    create mask = 0777
    directory mask = 0777
    force create mode = 0777
    force directory mode = 0777
    browsable =yes
    force user = $SHARE_USER
    force group = $SHARE_USER
EOF
        
        if [[ "$SERVER_TYPE" == *"1C"* ]]; then
            cat >> /etc/samba/smb.conf << EOF

[BIT_1C_tech_logs]
    path = /var/log/bit_monitoring/1C_tech_logs
    read only = no
    browsable = yes
    public = yes
    writable = yes
    read only = no
    guest ok = yes
    create mask = 0777
    directory mask = 0777
    force create mode = 0777
    force directory mode = 0777
    browsable =yes
    force user = $SHARE_USER
    force group = $SHARE_USER

[BIT_ClusterFoldersSizeLogs]
    path = /var/log/bit_monitoring/cluster_folders_sizes_logs
    read only = no
    browsable = yes
    public = yes
    writable = yes
    read only = no
    guest ok = yes
    create mask = 0777
    directory mask = 0777
    force create mode = 0777
    force directory mode = 0777
    browsable =yes
    force user = $SHARE_USER
    force group = $SHARE_USER
EOF
        fi
        
        # Перезапускаем Samba
        systemctl restart smbd
        
        # Устанавливаем пароль для пользователя Samba
        echo "Установите пароль для пользователя $SHARE_USER в Samba:"
        smbpasswd -a "$SHARE_USER"
    fi
}

# Основная функция
main() {
    # Проверяем права суперпользователя
    if [ "$EUID" -ne 0 ]; then 
        echo "ERROR: этот скрипт должен запускаться с правами root"
        exit 1
    fi
    
    # Парсим аргументы
    parse_arguments "$@"
    
    # Проверяем параметры
    check_parameters
    
    # Настраиваем логирование
    setup_logging
    
    # Настраиваем службу RAS (для 1С)
    setup_ras_service

    # Настраиваем доступ к логам
    setup_share_access
    
    echo "-------------------------------------------------------------------------------------------------"
    echo "Настройка завершена!"
    echo ""
    echo "Проверьте:"
    echo "1. Логи счетчиков сервера доступны в /var/log/bit_monitoring/server_counters_logs"
    echo "2. Сетевые папки логов доступны пользователю $SHARE_USER"    
    
    if [[ "$SERVER_TYPE" == *"1C"* ]]; then
        echo "3. Служба RAS запущена: systemctl status ras"
        echo "4. Логи тех. журнала 1С доступны в /var/log/bit_monitoring/1C_tech_logs"
        echo "5. Размеры папок кластера 1С сохраняются в /var/log/bit_monitoring/cluster_folders_sizes_logs"
    fi
}

# Запуск основной функции
main "$@"