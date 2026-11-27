# 🚀 LuCI App DoanDuy Modem & 5G Sentinel Suite (`v2.6.0` — Ultra-Fast Dialer & Universal Auto-Mesh)

Ứng dụng quản trị chuyên sâu dành cho Modem 5G PCIe & USB (Sierra Wireless EM9190 / Snapdragon SDX55, Quectel RM500Q/RM520N, Fibocom, MediaTek T-Series) + Auto-Mesh Đa Chip & Nhà Thông Minh Đa Năng trên nền tảng **ImmortalWrt / OpenWrt** (Qualcomm IPQ807x, IPQ60xx, MediaTek Filogic, x86).

---

## 🗂️ Cấu Trúc Tách Kịch Bản Độc Lập (`v2.6.0` — 7 Nhóm Độc Lập)

Toàn bộ mã nguồn được **tách thành 7 nhóm kịch bản độc lập** (xem bản đồ chi tiết tại [`SCENARIO_INDEX.md`](./SCENARIO_INDEX.md) và thư mục [`scenarios/`](./scenarios/)):

| Nhóm | Thư Mục Kịch Bản | Chức Năng & Module Phụ Trách |
| :--- | :--- | :--- |
| **01** | [`scenarios/01-dialer-watchdog/`](./scenarios/01-dialer-watchdog/README.md) | Trình quay số siêu tốc `duydoan5g` (~1.5s QMI/MBIM Fast-Path, chống rò khóa FD) & Watchdog tự phục hồi |
| **02** | [`scenarios/02-sim-sms/`](./scenarios/02-sim-sms/README.md) | Quản lý SIM, giải mã/gửi SMS tiếng Việt UCS2, hẹn giờ SMS (`doanduy/tab_sms.js`) |
| **03** | [`scenarios/03-rf-band-imei/`](./scenarios/03-rf-band-imei/README.md) | Sóng 5G, Khóa Băng Tần/PCI, Đổi IMEI, TTL & Lệnh AT (`doanduy/tab_modem.js`) |
| **04** | [`scenarios/04-sentinel-telegram-remote/`](./scenarios/04-sentinel-telegram-remote/README.md) | Đa Bot Telegram, AI Sentinel, Két Key & Camera/Tailscale (`doanduy/tab_sentinel.js`) |
| **05** | [`scenarios/05-adshield-optimizer/`](./scenarios/05-adshield-optimizer/README.md) | AdShield tương thích PassWall, Auto-Optimizer NSS/HNAT/WED & Khung điều phối LuCI |
| **06** | [`scenarios/06-smarthome/`](./scenarios/06-smarthome/README.md) | Nhà thông minh tự nhận diện qua IP, không giới hạn loại thiết bị & nút lệnh (5 module Lua + 2 module JS) |
| **07** | [`scenarios/07-auto-mesh/`](./scenarios/07-auto-mesh/README.md) | Auto-Mesh Đa Chip tự động: có mạng làm Chính (`192.168.1.1`), không mạng làm Phụ (`192.168.1.10`), hết Mesh tự về mặc định |

### ⚡ Kiểm Tra Hoặc Nạp Riêng Từng Kịch Bản (Windows PowerShell & Linux/CI)
```powershell
# Kiểm tra cú pháp + chuẩn LF riêng Kịch bản 06 (hoặc all cho cả 6 nhóm):
.\scenarios\run_scenario.ps1 -Group 06 -Action check

# Nạp nóng riêng Kịch bản 06 lên Router 192.168.1.1 (không đụng 5 nhóm còn lại):
.\scenarios\run_scenario.ps1 -Group 06 -Action deploy -RouterIp 192.168.1.1
```

---

## 🌟 Tính Năng & Kịch Bản Phân Rã (Modular Scenarios)

### 📬 Kịch Bản 1: Quản Lý SIM & Hộp Thư SMS PCIe Thông Minh
* Hỗ trợ đọc và gửi SMS qua cổng AT `/dev/wwan0at0` hoặc QMI WMS `/dev/wwan0qmi0`.
* Giải mã chuẩn xác **tiếng Việt Unicode UCS2 / UTF-8** không lỗi font.
* Hiển thị danh thiếp tin nhắn trực quan, nút **📋 Sao Chép (Copy 1-click)** mã OTP / cước data và xóa tin nhắn an toàn.
* Tự động quét 2 vùng nhớ SIM (`SM`) và Modem (`ME`).

### 📶 Kịch Bản 2: Quản Trị Sóng 5G, Khóa Băng Tần (Band Locking) & Lệnh AT
* Khóa băng tần linh hoạt: LTE B1/B3/B7/B8/B20/B28 & 5G NR N1/N3/N28/N41/N77/N78.
* Khóa trạm phát sóng di động (PCI / Cell Lock) cố định trạm sóng khỏe nhất.
* Chỉnh sửa **TTL (Time to Live)** chống bóp băng thông khi phát hotspot.
* Thiết bị đầu cuối lệnh AT (AT Terminal) tương tác trực tiếp với modem.

### 🛡️ Kịch Bản 3: Tự Động Nhận Biết Nhà Mạng Thu Hồi IP & Warm Reset Khôi Phục Tức Thì
* **Tự nhận biết khi mất IP WAN:** Khi mạng di động thay đổi trạng thái hoặc thu hồi IP, Watchdog nhận biết ngay trong 15-20 giây.
* **Warm Baseband Reset (`AT+CFUN=1,1` / `AT!RESET`):** Tự động ra lệnh khởi động lại chip baseband của modem, giải phóng bộ nhớ đệm PCIe MHI và cấp lại IP WAN mới tức thì.
* **Không Tự Ý Ngắt Mạng Định Kỳ:** Tuyệt đối không chủ động ngắt phiên mạng đang hoạt động; chỉ can thiệp leo thang 4 cấp (Nudge DHCP -> Redial -> Warm Reset -> Cellular USB Re-enumerate) khi thực sự rớt kết nối.

### 🤖 Kịch Bản 4: Quản Lý Không Giới Hạn Camera IP & Đa Bot Telegram
* Quản lý động danh sách Camera IP RTSP không giới hạn số lượng.
* Quản lý đa Bot Telegram: Từng Bot chuyên trách cho từng Camera, Bot báo trộm, Bot báo cháy khói, Kênh/Nhóm gia đình.
* Nút **⚡ Test Bot** kiểm tra trực tiếp kết nối Telegram API ngay trên trình duyệt.

### 🔐 Kịch Bản 5: Két Sắt Bảo Mật Tuyệt Đối (Zero-Leak Vault)
* Lưu trữ an toàn Gemini AI Key, Tailscale Auth Key, Telegram Token với quyền `chmod 600`.
* **Bảo Mật Hệ Thống Cấp Doanh Nghiệp:** Tự động bảo vệ các tham số thiết bị và mã định danh phần cứng (Cryptographic Hash Verification), ngăn ngừa truy cập trái phép từ bên ngoài.

---

## 📦 Hướng Dẫn Cài Đặt (Installation)

### Cách 1: Thêm vào Feeds trong Firmware OpenWrt (Khuyên dùng)
Thêm dòng sau vào file `feeds.conf.default` trong mã nguồn build OpenWrt của bạn:
```text
src-git doanduy https://github.com/Doanduy09/luci-app-doanduy-modem.git
```
Sau đó cập nhật và cài đặt feed:
```bash
./scripts/feeds update doanduy
./scripts/feeds install -a -p doanduy
make menuconfig
# Chọn: LuCI -> 3. Applications -> <*> luci-app-doanduy-modem
```

### Cách 2: Cài trực tiếp trên Router đang chạy (Hỗ trợ song song `.ipk` và `.apk`)
Tải gói tương ứng từ mục [Releases](https://github.com/Doanduy09/luci-app-doanduy-modem/releases):

**1. OpenWrt / ImmortalWrt <= 24.10 (chuẩn `opkg` `.ipk`):**
```bash
opkg update
opkg install luci-app-doanduy-modem_*.ipk
/etc/init.d/rpcd restart
/etc/init.d/uhttpd restart
```

**2. OpenWrt / ImmortalWrt 25.12 / 26+ (chuẩn `apk` `.apk` mới):**
```bash
apk add --no-network --allow-untrusted luci-app-doanduy-modem-*.apk || apk add --allow-untrusted luci-app-doanduy-modem-*.apk
/etc/init.d/rpcd restart
/etc/init.d/uhttpd restart
```

---

## 📜 Bản Quyền & Tác Giả
* **Tác giả:** DOANDUY (doanduy09@gmail.com)
* **Giấy phép:** GNU General Public License v3.0 (GPL-3.0)
