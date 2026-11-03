# Lenovo ThinkServer RD450X Smart Fan Control

[RU] Скрипт для интеллектуального и плавного управления вентиляторами на серверных материнских платах Lenovo RD450X (и аналогичных с поддержкой `ipmitool raw 0x2e 0x30`) под управлением Linux. 

[EN] Bash script for smart, smooth, and asymmetrical fan speed control on Lenovo RD450X server motherboards using `ipmitool`.

---

## Особенности / Features

* **Асимметричная регулировка (Asymmetric Step):** При росте нагрузки обороты взлетают **мгновенно**, защищая CPU. При падении нагрузки вентиляторы остывают **плавно** (шагами по 10%), избавляя от резкого шума.
* **Зона нечувствительности (Deadband / `MIN_STEP`):** Скрипт игнорирует колебания температуры в 1-2°C, не спамит команды в BMC и бережет ресурс кулеров.
* **Безопасность (Fault Tolerance):** Если IPMI зависнет или датчики вернут ошибку, скрипт автоматически выкрутит кулеры на **100%**.
* **Защита от дублирования:** Контроль PID-файла предотвращает одновременный запуск двух копий.

---

## Установка и настройка / Installation

### 1. Требования / Prerequisites
Убедитесь, что установлена утилита `ipmitool`:
```bash
sudo apt install ipmitool
```

### 2. Загрузка скрипта / Script Setup
Скачайте скрипт, перенесите его в системную директорию и сделайте исполняемым:
```bash
sudo cp cpu_temp_monitor.sh /usr/local/bin/
sudo chmod +x /usr/local/bin/cpu_temp_monitor.sh
```

### 3. Настройка автозапуска / Systemd Service
Создайте файл службы:
```bash
sudo nano /etc/systemd/system/cpu_temp_monitor.service
```
Вставьте содержимое файла `cpu_temp_monitor.service` из этого репозитория.

Запустите и активируйте службу:
```bash
sudo systemctl daemon-reload
sudo systemctl enable --now cpu_temp_monitor.service
```

### 4. Проверка статуса / Verification
```bash
sudo systemctl status cpu_temp_monitor.service
```

## Конфигурация / Configuration
Вы можете изменить пороги температур и шаги плавности в самом начале файла `/usr/local/bin/cpu_temp_monitor.sh`:
* `LOG_FILE` — LOG - файл. По умолчанию отключен. Чтоб включить поменяйте строчку на LOG_FILE="/var/log/cpu_temp_monitor.log"
* `TEMP_MIN` / `TEMP_MAX` — температурный диапазон работы.
* `MIN_FAN` / `MAX_FAN` — границы скорости вентиляторов в %.
* `MAX_STEP` — максимальный шаг снижения оборотов (по умолчанию 10%).
* `MIN_STEP` — мертвая зона (по умолчанию 3%).
