# 🗂️ Bản Đồ Phân Tách 6 Nhóm Kịch Bản (DOANDUY Modular Architecture v2.5.0)

Toàn bộ kho mã `luci-app-doanduy-modem` được chia thành **6 nhóm kịch bản độc lập hoàn toàn** để quản lý, kiểm tra lỗi và nâng cấp từng phần — **kịch bản nào cần nâng cấp thì chỉ sửa đúng nhóm đó, tuyệt đối không chạm vào các nhóm đang chạy ổn định (`[VERIFIED-GOLDEN]`)**.

## Danh Mục 6 Nhóm Kịch Bản

| Thư mục nhóm kịch bản | Chức năng đảm nhiệm | Quy mô | Kiểm tra nhanh (Windows PC) |
| :--- | :--- | :---: | :--- |
| [`scenarios/01-dialer-watchdog`](./scenarios/01-dialer-watchdog/README.md) | **Trình Quay Số 5G Thông Minh (USB & PCIe) & Watchdog Tự Phục Hồi** | 7 tệp | `./scenarios/01-dialer-watchdog/check.ps1` |
| [`scenarios/02-sim-sms`](./scenarios/02-sim-sms/README.md) | **Quản Lý SIM, Lịch Gia Hạn Tự Động & Hộp Thư SMS (USB & PCIe)** | 5 tệp | `./scenarios/02-sim-sms/check.ps1` |
| [`scenarios/03-rf-band-imei`](./scenarios/03-rf-band-imei/README.md) | **Modem 5G, Khóa Băng Tần, Khóa Trạm BTS, IMEI Luhn & TTL** | 5 tệp | `./scenarios/03-rf-band-imei/check.ps1` |
| [`scenarios/04-sentinel-telegram-remote`](./scenarios/04-sentinel-telegram-remote/README.md) | **Telegram Đa Bot, AI Sentinel, Kho Key Đa Tài Khoản & Kết Nối Từ Xa** | 7 tệp | `./scenarios/04-sentinel-telegram-remote/check.ps1` |
| [`scenarios/05-adshield-optimizer`](./scenarios/05-adshield-optimizer/README.md) | **Chặn Quảng Cáo AdShield, Tối Ưu Phần Cứng, Đọc Log & Khung Hệ Thống** | 12 tệp | `./scenarios/05-adshield-optimizer/check.ps1` |
| [`scenarios/06-smarthome`](./scenarios/06-smarthome/README.md) | **Nhà Thông Minh Tự Nhận Diện IP, Thiết Bị Vô Hạn, S06 IR & Voice ESP32** | 10 tệp | `./scenarios/06-smarthome/check.ps1` |

---

## Cấu Trúc Module Hóa Đã Tách Nhỏ Bên Trong Gói

1. **Backend Nhà Thông Minh (`scenarios/06-smarthome`)** — tách từ 1 file 2.856 dòng thành **6 tệp chuyên biệt**:
   - `root/usr/libexec/rpcd/doanduy.smarthome`: Bộ điều phối RPCD mỏng gọn (~105 dòng).
   - `root/usr/lib/lua/doanduy/smarthome/net_json.lua`: JSON 3 tầng + HTTP/TCP/UDP thuần `nixio` + Chống SSRF.
   - `root/usr/lib/lua/doanduy/smarthome/store.lua`: Kho khóa `chmod 600` + Quản lý thiết bị & bộ điều khiển v2.
   - `root/usr/lib/lua/doanduy/smarthome/catalog.lua`: 11 hãng Máy lạnh tự động + Kho IRDB Online 3.200+ thiết bị.
   - `root/usr/lib/lua/doanduy/smarthome/discovery.lua`: Tự nhận diện khi dán IP (`probeIp`) & Quét nhanh cả mạng LAN (`scanLanSmartDevices`).
   - `root/usr/lib/lua/doanduy/smarthome/drivers.lua`: 12 trình điều khiển thiết bị + Nút hành động tùy biến không giới hạn.

2. **Giao Diện LuCI (`htdocs/luci-static/resources/`)** — tách theo từng Tab độc lập:
   - `view/modem/control.js`: Khung điều hướng trung tâm mỏng gọn (~125 dòng).
   - `doanduy/tab_sms.js`: Riêng cho **Nhóm 02 (Quản lý SIM & SMS)**.
   - `doanduy/tab_modem.js`: Riêng cho **Nhóm 03 (Modem 5G, Băng tần & Lệnh AT)**.
   - `doanduy/tab_sentinel.js`: Riêng cho **Nhóm 04 (Telegram, AI Sentinel & Từ xa)**.
   - `doanduy/smarthome.js` & `doanduy/smarthome_modal.js`: Riêng cho **Nhóm 06 (Nhà thông minh tự nhận diện IP & thiết bị vô hạn)**.

---

## Cách Chạy Trên Máy Tính Anh Duy & Trên GitHub

```powershell
# 1. Xem danh sách toàn bộ 6 nhóm kịch bản trên máy tính:
.\scenarios\run_scenario.ps1 -Action list

# 2. Kiểm tra riêng 1 nhóm (VD: chỉ kiểm tra nhóm Nhà Thông Minh):
.\scenarios\run_scenario.ps1 -Group 06-smarthome -Action check

# 3. Đẩy nóng riêng 1 nhóm lên Router 192.168.1.1 (5 nhóm còn lại giữ nguyên 100%):
.\scenarios\run_scenario.ps1 -Group 06-smarthome -Action deploy -Router 192.168.1.1
```
