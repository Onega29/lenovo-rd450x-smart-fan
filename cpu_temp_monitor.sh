#!/bin/bash

# Конфигурация
LOG_FILE="dev/null" #"/var/log/cpu_temp_monitor.log"
LOCK_FILE="/var/run/cpu_temp_monitor.pid"

CHECK_INTERVAL=5   # Интервал проверки, секунд

TEMP_MIN=40        # При этой температуре и ниже — MIN_FAN
TEMP_MAX=70        # При этой температуре и выше — MAX_FAN
MIN_FAN=15         # Минимальная скорость, %
MAX_FAN=100        # Максимальная скорость, %

# Настройки плавности
MAX_STEP=5        # Максимальное снижение скорости за один цикл, %
MIN_STEP=5         # Минимальное изменение скорости для отправки команды, %

CURRENT_FAN=30     # Стартовая скорость, % (виртуальное начальное значение)

# Защита от дублирования
if [ -f "$LOCK_FILE" ]; then
    if ps -p "$(cat "$LOCK_FILE")" >/dev/null 2>&1; then
        echo "Ошибка: Скрипт уже запущен (PID: $(cat "$LOCK_FILE"))" | tee -a "$LOG_FILE"
        exit 1
    else
        rm -f "$LOCK_FILE"
    fi
fi
echo $$ > "$LOCK_FILE"
trap 'rm -f "$LOCK_FILE"; exit' SIGINT SIGTERM

# Установка скорости вентиляторов: значение передаётся как проценты
set_fan_speed() {
    local percent=$1

    # Ограничиваем диапазон
    (( percent < MIN_FAN )) && percent=$MIN_FAN
    (( percent > MAX_FAN )) && percent=$MAX_FAN

    # Отправляем raw-команду на плату Lenovo RD450X
    ipmitool raw 0x2e 0x30 00 00 "$percent" >> "$LOG_FILE" 2>&1

    if [ "$percent" -ne "$CURRENT_FAN" ]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Установлена скорость вентиляторов: ${percent}%" >> "$LOG_FILE"
    fi

    CURRENT_FAN=$percent
}

# Получение температуры с обработкой ошибок
get_cpu_temp() {
    local sensor=$1
    local temp
    temp=$(ipmitool sensor reading "$sensor" 2>/dev/null | awk '{print $NF}' | tr -dc '0-9')

    if [[ -z "$temp" || ! "$temp" =~ ^[0-9]+$ ]]; then
        echo "ERROR"
        return 1
    fi

    echo "$temp"
}

# Расчёт целевой скорости по максимальной температуре CPU
calc_target_fan() {
    local temp=$1

    if (( temp <= TEMP_MIN )); then
        echo "$MIN_FAN"
        return
    fi

    if (( temp >= TEMP_MAX )); then
        echo "$MAX_FAN"
        return
    fi

    local temp_range=$(( TEMP_MAX - TEMP_MIN ))
    local fan_range=$(( MAX_FAN - MIN_FAN ))
    local temp_offset=$(( temp - TEMP_MIN ))

    echo $(( MIN_FAN + temp_offset * fan_range / temp_range ))
}

# При старте принудительно инициализируем скорость
set_fan_speed "$CURRENT_FAN"

# Основной цикл мониторинга
while true; do
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    temp1=$(get_cpu_temp "CPU1 Temp")
    temp2=$(get_cpu_temp "CPU2 Temp")

    # Безопасность: Если датчик недоступен — включаем 100%
    if [[ "$temp1" == "ERROR" || "$temp2" == "ERROR" ]]; then
        echo "[$timestamp] КРИТИЧЕСКАЯ ОШИБКА: Датчик недоступен (CPU1=${temp1}, CPU2=${temp2}). Включаем кулеры на 100%!" >> "$LOG_FILE"
        set_fan_speed "$MAX_FAN"
        sleep "$CHECK_INTERVAL"
        continue
    fi

    max_temp=$(( temp1 > temp2 ? temp1 : temp2 ))
    target_fan=$(calc_target_fan "$max_temp")

    # Вычисляем разницу
    diff=$(( target_fan - CURRENT_FAN ))

    # Берем модуль разницы (абсолютное значение)
    abs_diff=${diff#-}

    if (( abs_diff >= MIN_STEP )); then
        # Асимметричная регулировка: вверх — сразу, вниз — плавно
        if (( diff > 0 )); then
            # Нагрев: выставляем целевую скорость мгновенно
            set_fan_speed "$target_fan"
            echo "[$timestamp] CPU1: ${temp1}°C, CPU2: ${temp2}°C | НАГРЕВ -> Скорость: ${target_fan}%" >> "$LOG_FILE"
        elif (( diff < 0 )); then
            # Остывание: снижаем скорость плавно, но не более чем на MAX_STEP
            (( diff < -MAX_STEP )) && diff=-MAX_STEP
            new_fan=$(( CURRENT_FAN + diff ))
            set_fan_speed $new_fan
            echo "[$timestamp] CPU1: ${temp1}°C, CPU2: ${temp2}°C | ОХЛАЖДЕНИЕ -> Скорость: ${new_fan}% (Цель: ${target_fan}%)" >> "$LOG_FILE"
        fi
    else
        # Разница незначительна — просто логируем текущие показатели
        echo "[$timestamp] CPU1: ${temp1}°C, CPU2: ${temp2}°C | Стабильно: ${CURRENT_FAN}% (Цель: ${target_fan}%)" >> "$LOG_FILE"
    fi

    sleep "$CHECK_INTERVAL"
done
