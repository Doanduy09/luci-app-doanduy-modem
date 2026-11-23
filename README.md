# 🚀 LuCI App DoanDuy Modem & 5G Sentinel Suite

Ứng dụng quản trị chuyên sâu dành cho Modem 5G PCIe (Sierra Wireless EM9190 / Snapdragon SDX55, Quectel RM500Q/RM520N, Fibocom) trên nền tảng **ImmortalWrt / OpenWrt** (Qualcomm IPQ8074, IPQ6000, MediaTek Filogic, x86).

---

## 🌟 Tính Năng & Kịch Bản Phân Rã (Modular Scenarios)

### 📬 Kịch Bản 1: Quản Lý SIM VIP & Hộp Thư SMS PCIe Thông Minh
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
* **Tự nhận biết khi mất IP WAN:** Khi nhà mạng thu hồi IP ngẫu nhiên sau 1-2 ngày, Watchdog nhận biết ngay trong 15-20 giây.
* **Warm Baseband Reset (`AT+CFUN=1,1` / `AT!RESET`):** Tự động ra lệnh khởi động lại chip baseband của modem, xả sạch 100% RAM rác và phân mảnh Ring Buffer DMA PCIe MHI, cấp lại IP WAN mới tức thì.
* **Lịch gia hạn khung giờ vàng (01:25:30):** Tự động gửi SMS gia hạn gói cước (5G150N), xác nhận Y và làm mới IP sạch sẽ mỗi ngày.

### 🤖 Kịch Bản 4: Quản Lý Không Giới Hạn Camera IP & Đa Bot Telegram
* Quản lý động danh sách Camera IP RTSP không giới hạn số lượng.
* Quản lý đa Bot Telegram: Từng Bot chuyên trách cho từng Camera, Bot báo trộm, Bot báo cháy khói, Kênh/Nhóm gia đình.
* Nút **⚡ Test Bot** kiểm tra trực tiếp kết nối Telegram API ngay trên trình duyệt.

### 🔐 Kịch Bản 5: Két Sắt Bảo Mật Tuyệt Đối (Zero-Leak Vault)
* Lưu trữ an toàn Gemini AI Key, Tailscale Auth Key, Telegram Token với quyền `chmod 600`.
* Bảo vệ ICCID SIM VIP: SIM không nằm trong danh sách mặc định sẽ tự động bị ẩn (Stealth mode) và khóa toàn bộ quyền gửi SMS để bảo vệ tài khoản.

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

### Cách 2: Cài trực tiếp file `.ipk` trên Router đang chạy
```bash
opkg update
opkg install luci-app-doanduy-modem*.ipk
/etc/init.d/rpcd restart
/etc/init.d/uhttpd restart
```

---

## 📜 Bản Quyền & Tác Giả
* **Tác giả:** DOANDUY (doanduy09@gmail.com)
* **Giấy phép:** GNU General Public License v3.0 (GPL-3.0)
