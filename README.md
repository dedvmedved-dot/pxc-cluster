# Percona XtraDB Cluster — Отказоустойчивый кластер MySQL

## Содержание

1. [Цель проекта](#1-цель-проекта)
2. [Архитектура кластера](#2-архитектура-кластера)
3. [Использованные технологии](#3-использованные-технологии)
4. [Создание инфраструктуры](#4-создание-инфраструктуры)
5. [Установка и настройка PXC](#5-установка-и-настройка-pxc)
6. [Как работает Galera Replication](#6-как-работает-galera-replication)
7. [Проблемы и их решение](#7-проблемы-и-их-решение)
8. [Проверка работы кластера](#8-проверка-работы-кластера)
9. [Структура проекта](#9-структура-проекта)
10. [Реальные применения](#10-реальные-применения)

---

## 1. Цель проекта

Создать отказоустойчивый кластер MySQL из трёх узлов на базе **Percona XtraDB Cluster (PXC)** с синхронной репликацией Galera. Кластер должен обеспечивать:

- **Multi-master** — запись на любую ноду
- **Синхронную репликацию** — данные мгновенно появляются на всех узлах
- **Автоматическое восстановление** — при отказе ноды кластер продолжает работу

---

## 2. Архитектура кластера

### Схема: Архитектура Percona XtraDB Cluster
![Архитектура Percona XtraDB Cluster](screenshots/PXC_Architecture.svg)
---


### Описание архитектуры

**Percona XtraDB Cluster** — это кластерное решение на основе MySQL с использованием **Galera Replication**. Три ноды образуют кластер, где каждая нода:

- Принимает чтение и запись (multi-master)
- Синхронно реплицирует изменения на другие ноды
- Хранит полную копию данных
- Может заменить любую другую ноду при отказе

**Сетевые порты:**
- `3306` — MySQL-клиенты
- `4567` — Galera gcomm (групповая коммуникация)
- `4568` — IST (Incremental State Transfer)
- `4444` — SST (State Snapshot Transfer)

---

## 3. Использованные технологии

### Схема: Технологический стек
![Технологический стек](screenshots/TechStack.svg)
---


### Описание технологий

**Percona XtraDB Cluster** — это комбинация трёх компонентов:
1. **Percona Server for MySQL** — сервер базы данных, совместимый с MySQL 8.0
2. **Galera Replication** — библиотека синхронной multi-master репликации
3. **Percona XtraBackup** — инструмент горячего резервного копирования, используемый для SST

**Galera Replication** обеспечивает:
- **Синхронную репликацию** — транзакция фиксируется только после подтверждения всеми нодами
- **Сертификацию** — проверка конфликтов перед применением
- **Автоматическое восстановление** — нода, отставшая от кластера, получает недостающие данные через IST или SST

---

## 4. Создание инфраструктуры

### Схема: Процесс создания ВМ через Terraform

```dot
digraph TerraformFlow {
    label="Создание инфраструктуры через Terraform";
    labelloc=t;
    fontsize=18;
    fontname="Arial";
    rankdir=TB;
    splines=ortho;
    nodesep=0.6;
    ranksep=0.5;
    
    node [shape=box, style=rounded, fontname="Arial", fontsize=10];
    
    start [label="Старт", shape=oval, fillcolor="#E8F0FE", style=filled];
    
    step1 [label="terraform init\nЗагрузка провайдера\nlibvirt 0.7.1\nиз локального кэша", fillcolor="#FCE8E6", style=filled];
    step2 [label="terraform plan\nЧтение main.tf\nПлан: 10 ресурсов\n3 ВМ + диски +\ncloud-init ISO", fillcolor="#E6F4EA", style=filled];
    step3 [label="terraform apply\nСоздание:\n- libvirt_volume.ubuntu_image\n  (образ Ubuntu 22.04)\n- libvirt_volume.disk (×3)\n  (диски ВМ по 20 ГБ)\n- libvirt_cloudinit_disk (×3)\n  (SSH-ключи)\n- libvirt_domain.vm (×3)\n  (виртуальные машины)", fillcolor="#FFF3E0", style=filled];
    step4 [label="Проблема: DHCP не выдал IP\nРешение: DHCP-резервации\nпо MAC-адресам\n+ перезапуск libvirtd", fillcolor="#FFCDD2", style=filled];
    
    end [label="3 ВМ запущены\npxc-node1: 192.168.122.31\npxc-node2: 192.168.122.32\npxc-node3: 192.168.122.33", shape=oval, fillcolor="#C8E6C9", style=filled];
    
    start -> step1;
    step1 -> step2;
    step2 -> step3;
    step3 -> step4;
    step4 -> end;
}
```

### Конфигурация Terraform

ВМ создаются со следующими параметрами:
- **ОС:** Ubuntu 22.04 Cloud Image
- **RAM:** 2 ГБ
- **CPU:** 2 ядра
- **Диск:** 20 ГБ
- **Сеть:** NAT (192.168.122.0/24)
- **Доступ:** SSH-ключ через cloud-init

---

## 5. Установка и настройка PXC

### Схема: Процесс настройки через Ansible

```dot
digraph AnsibleFlow {
    label="Настройка кластера через Ansible";
    labelloc=t;
    fontsize=18;
    fontname="Arial";
    rankdir=TB;
    splines=ortho;
    nodesep=0.6;
    ranksep=0.5;
    
    node [shape=box, style=rounded, fontname="Arial", fontsize=10];
    
    start [label="ansible-playbook\ndeploy.yml", shape=oval, fillcolor="#E8F0FE", style=filled];
    
    role1 [label="Роль 1: Установка\n- Добавление репозитория Percona\n- percona-release setup pxc-80\n- apt install percona-xtradb-cluster\n- Установка xtrabackup\n- Установка socat", fillcolor="#E6F4EA", style=filled];
    
    role2 [label="Роль 2: Конфигурация\n- Шаблон /etc/mysql/my.cnf\n  с Jinja2-переменными\n- wsrep-cluster-address\n  зависит от имени хоста\n- wsrep-node-address\n  разный для каждой ноды\n- Отключение SSL для Galera\n  (socket.ssl=false)", fillcolor="#E6F4EA", style=filled];
    
    role3 [label="Роль 3: Запуск\n- pxc-node1: bootstrap\n  WSREP_NEW_CLUSTER=1\n- pxc-node2: подключение\n  к pxc-node1\n- pxc-node3: подключение\n  к pxc-node1 и pxc-node2", fillcolor="#E6F4EA", style=filled];
    
    role4 [label="Роль 4: Настройка SST\n- Создание sstuser\n- GRANT RELOAD, LOCK TABLES,\n  PROCESS, REPLICATION CLIENT\n- Пароль: SstPass123\n- Доступ с 192.168.122.%", fillcolor="#E6F4EA", style=filled];
    
    end [label="Кластер из 3 нод\nработает", shape=oval, fillcolor="#C8E6C9", style=filled];
    
    start -> role1;
    role1 -> role2;
    role2 -> role3;
    role3 -> role4;
    role4 -> end;
}
```

### Конфигурация my.cnf (шаблон Jinja2)

```ini
[mysqld]
wsrep-provider=/usr/lib/galera4/libgalera_smm.so
wsrep-provider-options="socket.ssl=false"
wsrep-cluster-name=pxc-cluster
wsrep-cluster-address=gcomm://192.168.122.31
wsrep-node-name=pxc-node2
wsrep-node-address=192.168.122.32
wsrep-sst-method=xtrabackup-v2
wsrep-sst-auth=sstuser:SstPass123
default-storage-engine=InnoDB
bind-address=0.0.0.0
```

**Ключевые параметры:**
- `wsrep-provider` — путь к библиотеке Galera
- `wsrep-cluster-address` — адреса нод для подключения (на pxc-node1 — `gcomm://` для bootstrap)
- `wsrep-node-address` — IP текущей ноды
- `wsrep-sst-method=xtrabackup-v2` — метод полной синхронизации
- `socket.ssl=false` — отключение SSL для Galera (решает проблему с самоподписанными сертификатами)

---

## 6. Как работает Galera Replication

### Схема: Процесс репликации транзакции

```dot
digraph GaleraReplication {
    label="Процесс синхронной репликации в Galera";
    labelloc=t;
    fontsize=18;
    fontname="Arial";
    rankdir=TB;
    splines=ortho;
    nodesep=0.7;
    ranksep=0.5;
    
    node [shape=box, style=rounded, fontname="Arial", fontsize=10];
    
    client [label="Клиент\nINSERT INTO users...", shape=oval, fillcolor="#E8F0FE", style=filled];
    
    step1 [label="1. Клиент отправляет\nтранзакцию на pxc-node1", fillcolor="#FCE8E6", style=filled];
    step2 [label="2. pxc-node1 выполняет\nтранзакцию локально\nи создаёт writeset", fillcolor="#FCE8E6", style=filled];
    step3 [label="3. pxc-node1 рассылает\nwriteset всем нодам\nчерез gcomm (порт 4567)", fillcolor="#FFF3E0", style=filled];
    step4 [label="4. Каждая нода\nсертифицирует writeset\n(проверяет конфликты)", fillcolor="#FFF3E0", style=filled];
    step5 [label="5. Если сертификация\nпройдена — нода\nприменяет writeset\nи отправляет ACK", fillcolor="#E6F4EA", style=filled];
    step6 [label="6. pxc-node1 получает\nACK от всех нод\nи подтверждает COMMIT\nклиенту", fillcolor="#E6F4EA", style=filled];
    
    client -> step1;
    step1 -> step2;
    step2 -> step3;
    step3 -> step4;
    step4 -> step5;
    step5 -> step6;
    step6 -> client [label="COMMIT OK", color="#34A853", penwidth=2];
    
    note [label="Важно: Если хотя бы одна нода\nне ответила — транзакция откатывается\nна всех узлах (atomic commit)", shape=note, fillcolor="#FFCDD2", style=filled];
    step5 -> note [style=dashed];
}
```

### Схема: Восстановление ноды (SST и IST)

```dot
digraph NodeRecovery {
    label="Механизмы восстановления ноды в кластере";
    labelloc=t;
    fontsize=18;
    fontname="Arial";
    rankdir=TB;
    splines=ortho;
    nodesep=0.7;
    ranksep=0.5;
    
    node [shape=box, style=rounded, fontname="Arial", fontsize=10];
    
    new_node [label="Новая нода\nподключается\nк кластеру", shape=oval, fillcolor="#E8F0FE", style=filled];
    
    decision [label="Проверка:\nЕсть ли недостающие\nтранзакции в gcache\nдонора?", shape=diamond, fillcolor="#FFF9C4", style=filled];
    
    ist_path [label="IST (Incremental)\n• Быстрая синхронизация\n• Передаются только\n  недостающие writeset-ы\n• Нода быстро входит\n  в строй", fillcolor="#A5D6A7", style=filled];
    
    sst_path [label="SST (Snapshot)\n• Полная синхронизация\n• xtrabackup копирует\n  всю БД с донора\n• Медленно (зависит\n  от размера БД)\n• Нода получает\n  полную копию данных", fillcolor="#FFCDD2", style=filled];
    
    synced [label="Нода синхронизирована\nSYNCED\nГотова к работе", shape=oval, fillcolor="#C8E6C9", style=filled];
    
    new_node -> decision;
    decision -> ist_path [label="Да\n(транзакции в кэше)"];
    decision -> sst_path [label="Нет\n(кэш очищен или\nнода новая)"];
    ist_path -> synced;
    sst_path -> synced;
}
```

---

## 7. Проблемы и их решение

### Схема: Путь через трудности

```dot
digraph Troubleshooting {
    label="Хронология проблем при настройке PXC";
    labelloc=t;
    fontsize=18;
    fontname="Arial";
    rankdir=TB;
    splines=ortho;
    nodesep=0.7;
    ranksep=0.5;
    
    node [shape=box, style=rounded, fontname="Arial", fontsize=10];
    
    start [label="Начало настройки", shape=oval, fillcolor="#E8F0FE", style=filled];
    
    p1 [label="Проблема 1: Синтаксис конфига\nwsrep_sst_auth → ошибка\n'unknown variable'\nПричина: Percona 8.0 использует\nдефисы вместо подчёркиваний", fillcolor="#FFCDD2", style=filled];
    s1 [label="Решение 1:\nЗаменили wsrep_sst_auth\nна wsrep-sst-auth\n(дефисы вместо подчёркиваний)", fillcolor="#C8E6C9", style=filled];
    
    p2 [label="Проблема 2: MySQL не стартует\n'wsrep-sst-auth' всё равно\nне принимается\nПричина: переменная невалидна\nв Percona 8.0.45", fillcolor="#FFCDD2", style=filled];
    s2 [label="Решение 2:\nУбрали wsrep-sst-auth из [mysqld]\nДобавили секцию [sst]\nsstuser и sstpassword отдельно", fillcolor="#C8E6C9", style=filled];
    
    p3 [label="Проблема 3: SSL-сертификаты\n'certificate signature failure'\n'failed to establish connection'\nПричина: самоподписанные\nсертификаты на разных нодах\nне совпадают", fillcolor="#FFCDD2", style=filled];
    s3 [label="Решение 3:\nwsrep-provider-options=\"socket.ssl=false\"\nОтключили SSL для Galera\nна всех нодах", fillcolor="#C8E6C9", style=filled];
    
    p4 [label="Проблема 4: SST не работает\n'Resource temporarily unavailable'\n'Will never receive state'\nПричина: xtrabackup не может\nпередать данные из-за сетевых\nограничений и ошибок socat", fillcolor="#FFCDD2", style=filled];
    s4 [label="Решение 4:\nРучное копирование /var/lib/mysql\nс pxc-node1 на остальные ноды\nчерез tar + scp\n+ очистка gcache и gvwstate.dat", fillcolor="#C8E6C9", style=filled];
    
    p5 [label="Проблема 5: pxc-node3 не подключается\n'Connection timed out'\nПричина: в wsrep-cluster-address\nуказан только pxc-node1,\nно pxc-node1 не принимает SST", fillcolor="#FFCDD2", style=filled];
    s5 [label="Решение 5:\nДобавили pxc-node2 в\nwsrep-cluster-address:\ngcomm://192.168.122.31,192.168.122.32\nНода подключилась через IST", fillcolor="#C8E6C9", style=filled];
    
    success [label="Кластер из 3 нод\nработает\nwsrep_cluster_size = 3", shape=oval, fillcolor="#A5D6A7", style=filled, penwidth=2];
    
    start -> p1;
    p1 -> s1;
    s1 -> p2;
    p2 -> s2;
    s2 -> p3;
    p3 -> s3;
    s3 -> p4;
    p4 -> s4;
    s4 -> p5;
    p5 -> s5;
    s5 -> success;
}
```

### Подробный разбор проблем

#### Проблема 1: Синтаксис конфигурации

**Симптом:** MySQL падает с ошибкой `unknown variable 'wsrep_sst_auth'`

**Причина:** В Percona XtraDB Cluster 8.0 изменился синтаксис конфигурации. Переменные используют **дефисы** вместо подчёркиваний:
- Было: `wsrep_sst_auth`, `wsrep_cluster_name`
- Стало: `wsrep-sst-auth`, `wsrep-cluster-name`

**Решение:** Полностью переписали шаблон my.cnf с использованием нового синтаксиса.

#### Проблема 2: wsrep-sst-auth не принимается

**Симптом:** Даже с дефисами `wsrep-sst-auth` вызывает фатальную ошибку при старте MySQL.

**Причина:** В версии 8.0.45 переменная `wsrep-sst-auth` не принимается в секции `[mysqld]`.

**Решение:** Вынесли параметры SST в отдельную секцию `[sst]`:
```ini
[sst]
sstuser=sstuser
sstpassword=SstPass123
```

#### Проблема 3: SSL-сертификаты Galera

**Симптом:** `certificate signature failure`, `Failed to establish connection: invalid padding`

**Причина:** Каждая нода PXC генерирует самоподписанные SSL-сертификаты при установке. Сертификаты разных нод не совпадают, и Galera не может установить защищённое соединение.

**Решение:** Добавили в конфиг `wsrep-provider-options="socket.ssl=false"` — полностью отключили SSL для групповой коммуникации Galera. В продакшн-среде следует использовать общий CA-сертификат.

#### Проблема 4: SST не передаёт данные (КЛЮЧЕВАЯ ПРОБЛЕМА)

**Симптом:** 
- `SST script aborted with error 11 (Resource temporarily unavailable)`
- `Will never receive state. Need to abort.`
- На доноре: `socat SSL_connect(): error:0200008A:rsa routines::invalid padding`

**Причина:** Это комбинация нескольких факторов:
1. **Socat + SSL** — xtrabackup-v2 использует socat для передачи данных. Проблемы с SSL-сертификатами (даже после отключения SSL для Galera) мешают socat установить соединение
2. **Сетевые ограничения** — iptables мог блокировать динамические порты SST
3. **Очищенная директория данных** — после `rm -rf /var/lib/mysql/*` система не может стартовать без системных таблиц

**Решение (workaround):**
1. Остановили MySQL на всех нодах
2. Сделали tar.gz копию `/var/lib/mysql` с работающей pxc-node1
3. Скопировали архив на pxc-node2 и pxc-node3 через scp
4. Распаковали с правильными правами (`chown -R mysql:mysql`)
5. Запустили кластер: сначала bootstrap pxc-node1, затем остальные

Этот метод имитирует успешный SST — ноды получают идентичную копию данных и могут синхронизироваться через IST.

#### Проблема 5: Третья нода не подключается

**Симптом:** pxc-node3 падает с `Connection timed out` при попытке подключиться к кластеру.

**Причина:** В `wsrep-cluster-address` был указан только pxc-node1 (`gcomm://192.168.122.31`). Если pxc-node1 не может обслужить SST (занят, проблемы с socat), нода не может войти в кластер.

**Решение:** Добавили pxc-node2 в `wsrep-cluster-address`: `gcomm://192.168.122.31,192.168.122.32`. Теперь pxc-node3 может подключиться к любой доступной ноде, а так как у неё уже есть данные (скопированы вручную), она синхронизируется через быстрый IST, а не SST.

---

## 8. Проверка работы кластера

### Схема: Тестирование кластера

```dot
digraph ClusterTest {
    label="Методика проверки работоспособности кластера";
    labelloc=t;
    fontsize=18;
    fontname="Arial";
    rankdir=TB;
    splines=ortho;
    nodesep=0.7;
    ranksep=0.5;
    
    node [shape=box, style=rounded, fontname="Arial", fontsize=10];
    
    test1 [label="Тест 1: Размер кластера\nSHOW STATUS LIKE\n'wsrep_cluster_size'\nОжидание: 3\nРезультат: 3 ✅", fillcolor="#C8E6C9", style=filled];
    
    test2 [label="Тест 2: Адреса нод\nSHOW STATUS LIKE\n'wsrep_incoming_addresses'\nОжидание: 3 адреса\nРезультат: все 3 ✅", fillcolor="#C8E6C9", style=filled];
    
    test3 [label="Тест 3: Создание БД\nCREATE DATABASE test_cluster\nна pxc-node1\nОжидание: БД появится\nна всех нодах\nРезультат: ✅", fillcolor="#C8E6C9", style=filled];
    
    test4 [label="Тест 4: Порты\nss -tlnp | grep 3306\nна всех нодах\nОжидание: слушается\nРезультат: ✅", fillcolor="#C8E6C9", style=filled];
    
    result [label="Кластер полностью\nработоспособен", shape=oval, fillcolor="#A5D6A7", style=filled, penwidth=2];
    
    test1 -> test2;
    test2 -> test3;
    test3 -> test4;
    test4 -> result;
}
```

### Результаты тестов

```
=== Cluster Size ===
wsrep_cluster_size = 3

=== Cluster Nodes ===
wsrep_incoming_addresses = 192.168.122.33:3306,192.168.122.31:3306,192.168.122.32:3306

=== Create Test DB ===
CREATE DATABASE test_cluster;

=== Check DB on all nodes ===
Node 192.168.122.31: test_cluster ✅
Node 192.168.122.32: test_cluster ✅
Node 192.168.122.33: test_cluster ✅

=== MySQL Status ===
Node 192.168.122.31: 2 port(s) listening ✅
Node 192.168.122.32: 2 port(s) listening ✅
Node 192.168.122.33: 2 port(s) listening ✅
```

---

## 9. Структура проекта

```
pxc-cluster/
├── terraform/
│   ├── main.tf              # 3 ВМ: pxc-node1, pxc-node2, pxc-node3
│   ├── outputs.tf           # IP-адреса нод
│   └── cloud-init.yaml      # SSH-ключи
├── ansible/
│   ├── inventory.ini        # Inventory для Ansible
│   ├── playbooks/
│   │   └── deploy.yml       # Плейбук развёртывания
│   └── roles/
│       └── pxc/
│           ├── tasks/
│           │   └── main.yml     # Установка и настройка PXC
│           ├── handlers/
│           │   └── main.yml     # Перезапуск MySQL
│           └── templates/
│               └── my.cnf.j2    # Шаблон конфигурации
├── screenshots/             # Скриншоты выполнения
└── README.md               # Документация
```

---

## 10. Реальные применения

### Где используются кластеры MySQL

| Сценарий | Примеры | Почему PXC |
|----------|---------|------------|
| **E-commerce** | Wildberries, Ozon | Нельзя терять заказы при отказе сервера БД |
| **FinTech** | Банки, платёжные системы | Транзакции должны быть атомарными и реплицированными |
| **SaaS** | CRM, ERP-системы | Высокая доступность для клиентов 24/7 |
| **Игровые серверы** | Мобильные игры | Синхронизация состояния игроков между серверами |
| **Телеком** | Биллинг, тарификация | Отказоустойчивость критических данных |

### Отличия PXC от стандартной репликации MySQL

| Характеристика | Стандартная репликация | Percona XtraDB Cluster |
|----------------|----------------------|----------------------|
| Тип репликации | Асинхронная | Синхронная |
| Запись | Только на master | На любую ноду |
| Отказ master | Ручное переключение | Автоматически |
| Конфликты | Возможны | Сертификация транзакций |
| Задержка | Может отставать | Всегда актуально |

---

**Проект выполнен. Percona XtraDB Cluster из 3 нод работает. Требования задания соблюдены.**

