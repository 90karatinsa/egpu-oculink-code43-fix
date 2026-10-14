# Fix NVIDIA Code 43 on an eGPU over M.2 → OCuLink

**A desktop NVIDIA GPU connected to a laptop through an M.2 NVMe → OCuLink adapter shows _Code 43_ in Device Manager and gives no picture. One registry value fixes it.**

🇹🇷 Türkçe açıklama aşağıda: [Türkçe](#türkçe)

Tested on **HP Victus 16** (i5-14500HX, RTX 4060 Laptop, BIOS F.20) + **MSI RTX 3090 SUPRIM X** via a generic M.2 → OCuLink adapter and OCuLink dock, Windows 11, NVIDIA 617.42 desktop driver. It should apply to other laptops whose M.2 slots have no PCIe hot-plug support (HP OMEN, other brands) and to other NVIDIA desktop cards — not tested there.

## Symptoms

- The GPU shows up in Device Manager **with its real name**, but with **Code 43** — *"Windows has stopped this device because it has reported problems."*
- The NVIDIA installer reports a failure, NVIDIA App only lists the laptop's own GPU.
- No picture from the eGPU's outputs.

Before the desktop driver is installed, the card may show as *Microsoft Basic Display Adapter* with **Code 10**. That is only a missing driver: install the regular **desktop** GeForce driver from nvidia.com first (the laptop maker's driver doesn't cover desktop cards). Code 43 comes after that.

## Cause

The NVIDIA driver refuses to start a desktop GPU on a PCIe port that is not hot-plug capable and reports Code 43. Laptop M.2 slots aren't: on the test machine the root port's *Slot Capabilities* register was `0x00042580` — the *Hot-Plug Capable* bit is 0.

The eGPU community skips this check with the driver setting **`RM1774520 = 1`**. It is the same change egpu.io's [nvidia-error43-fixer](https://egpu.io/nvidia-error43-fixer/) makes. NVIDIA does not document it.

## Fix

### Option A — script

1. Download `Fix-NvidiaEgpuCode43.ps1` and `fix-code43.cmd` into the same folder.
2. Power on the **dock and GPU first, then boot the laptop**, so the GPU is present (with Code 43).
3. Double-click `fix-code43.cmd` and accept the UAC prompt.
4. **Shut down completely** (not restart). Power on the dock and GPU, then the laptop.

The script finds every NVIDIA display device that reports Code 43 and writes `RM1774520 = 1` to the driver key of **every instance of that GPU model** — including instances left by other M.2 slots. It only uses built-in Windows cmdlets; nothing is downloaded or installed.

```powershell
.\Fix-NvidiaEgpuCode43.ps1 -DryRun                                  # preview, changes nothing, no admin needed
.\Fix-NvidiaEgpuCode43.ps1 -DeviceId 'PCI\VEN_10DE&DEV_2204'        # target a specific model (2204 = RTX 3090)
```

Your card's id: Device Manager → the GPU → Properties → Details → *Hardware Ids* → the `PCI\VEN_10DE&DEV_xxxx` part.

### Option B — by hand

1. Device Manager → the GPU → Properties → Details → **Driver key**, e.g. `{4d36e968-e325-11ce-bfc1-08002be10318}\0003`.
2. In `regedit`, open `HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Class\` + that driver key.
3. New → **DWORD (32-bit) Value** → name `RM1774520`, value `1`.
4. Shut down completely and cold boot (dock first).

Or one line in an **admin** PowerShell (replace `DEV_2204` with your card's id):

```powershell
Get-PnpDevice | ? { $_.InstanceId -like 'PCI\VEN_10DE&DEV_2204*' } | % { $d=(Get-PnpDeviceProperty -InstanceId $_.InstanceId -KeyName DEVPKEY_Device_Driver).Data; if ($d) { reg add "HKLM\SYSTEM\CurrentControlSet\Control\Class\$d" /v RM1774520 /t REG_DWORD /d 1 /f } }
```

## Good to know

- **A cold boot is required.** Disabling/enabling the device after adding the value turned Code 43 into **Code 31** (`0xC0000010`); a full shutdown and cold boot cleared it.
- **Boot order:** dock and GPU first, then the laptop. OCuLink is not hot-pluggable.
- **Re-apply after:** an NVIDIA *clean* install, removing the GPU in Device Manager, reinstalling Windows, or **moving the adapter to another M.2 slot**. Each of these creates a new device entry with a new driver key (seen in practice: the key moved from `\0003` to `\0000` after a driver reinstall). Just run the script again.
- **Graphics mode (MUX):** keep *Hybrid*. The laptop screen runs on the iGPU; plug the monitor into the eGPU.
- **No need to weaken Windows security.** Works with *Memory Integrity* (HVCI) and the *Microsoft Vulnerable Driver Blocklist* both **enabled** — verified on the test machine.
- **Red herring:** the HP BIOS writes its own subsystem id (`103C:8C99`) to the eGPU and locks it. It looks suspicious but isn't the problem — the card works with it.
- **Undo:** delete the `RM1774520` value and reboot.
- **If the eGPU drops out under load:** suspect the adapter and cable first. Try a shorter (30–50 cm) OCuLink cable or an M.2 adapter with a redriver chip. A bumped cable also makes the GPU "fall off the bus" until the next reboot.

`RM1774520` is undocumented. Use at your own risk.

## What did *not* fix it

Ten things were tested before the real cause was found. They may save you time:

| Tried | Result | What it showed |
|---|---|---|
| Cold boot, dock first | Code 43 | Needed for detection, not enough |
| Disable / enable in Device Manager | Code 43 | Not a one-off init failure |
| Power: 1200 W PSU, 3 separate PCIe cables, dock on 24-pin | fine | Power ruled out |
| Card in a desktop PC | works | Card is fine |
| Other M.2 slot (chipset ↔ CPU lanes) | Gen4 x4 link, still Code 43 | Slot ruled out |
| PCIe memory windows (BAR) | correct | No resource problem (Code 12) |
| PCIe error log (WHEA / AER) | only harmless *Unsupported Request* | No signal errors |
| Forcing PCIe Gen3 | Code 43 | Signal quality ruled out |
| Disabling the laptop's own GPU | Code 43 | Not a conflict with the iGPU/dGPU |
| Changing the card's subsystem id | registry locked | Not needed after all |

## Credits

The `RM1774520` setting comes from the egpu.io community and its [nvidia-error43-fixer](https://egpu.io/nvidia-error43-fixer/) tool.

---

## Türkçe

**Dizüstüne M.2 NVMe → OCuLink adaptörüyle bağlanan masaüstü NVIDIA ekran kartı, Aygıt Yöneticisi'nde _Kod 43_ veriyor ve görüntü vermiyor. Tek bir kayıt defteri değeriyle düzeliyor.**

Test edilen sistem: **HP Victus 16** (i5-14500HX, RTX 4060 Laptop, BIOS F.20) + **MSI RTX 3090 SUPRIM X**, markasız M.2 → OCuLink adaptör ve OCuLink dock, Windows 11, NVIDIA 617.42 masaüstü sürücüsü. M.2 yuvası PCIe hot-plug desteklemeyen başka dizüstülerde ve başka NVIDIA kartlarda da işe yaraması beklenir, ama test edilmedi.

### Belirtiler

- Kart Aygıt Yöneticisi'nde **kendi adıyla** görünüyor ama **Kod 43** veriyor: *"Windows bu aygıtı sorun bildirdiği için durdurdu."*
- NVIDIA kurulumu "başarısız" diyor, NVIDIA uygulaması sadece dizüstünün kendi kartını gösteriyor.
- Kartın çıkışlarından görüntü gelmiyor.

Masaüstü sürücüsü kurulmadan önce kart *Microsoft Temel Görüntü Bağdaştırıcısı* olarak **Kod 10** verebilir. Bu sadece sürücü eksikliği: önce nvidia.com'dan normal **masaüstü** GeForce sürücüsünü kurun (dizüstü üreticisinin sürücüsü masaüstü kartları kapsamaz). Kod 43 bundan sonra gelir.

### Sebep

NVIDIA sürücüsü, hot-plug (tak-çıkar) desteklemeyen bir PCIe portuna bağlı masaüstü kartını başlatmayı reddediyor ve Kod 43 veriyor. Dizüstülerin M.2 yuvaları hot-plug desteklemez: test makinesinde portun *Slot Capabilities* kaydı `0x00042580`, *Hot-Plug Capable* biti 0.

eGPU topluluğu bu kontrolü sürücü ayarı **`RM1774520 = 1`** ile atlatıyor. egpu.io'daki [nvidia-error43-fixer](https://egpu.io/nvidia-error43-fixer/) aracının yaptığı değişiklik de bu. NVIDIA bu ayarı resmi olarak belgelemiyor.

### Çözüm

**Betikle:**

1. `Fix-NvidiaEgpuCode43.ps1` ve `fix-code43.cmd` dosyalarını aynı klasöre indirin.
2. **Önce dock ve kartı, sonra dizüstünü** açın; kart Kod 43 ile görünür durumda olsun.
3. `fix-code43.cmd`'ye çift tıklayın, UAC'ye **Evet** deyin.
4. Dizüstünü **tamamen kapatın** (yeniden başlatmayın). Önce dock ve kartı, sonra dizüstünü açın.

Betik Kod 43 veren NVIDIA kartını kendisi bulur ve o modelin **bütün kayıtlarına** değeri yazar (başka M.2 yuvalarından kalanlar dahil). Sadece Windows'un kendi araçlarını kullanır, hiçbir şey indirmez. `-DryRun` ile önce ne yapacağını görebilirsiniz.

**Elle:** Aygıt Yöneticisi → kart → Özellikler → Ayrıntılar → **Sürücü anahtarı**'nı okuyun (örn. `{4d36e968-...}\0003`). `regedit` ile `HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Class\` altında o anahtarı açın, **DWORD (32 bit)** değer ekleyin: ad `RM1774520`, değer `1`. Tamamen kapatıp açın.

### Bilinmesi gerekenler

- **Soğuk açılış şart.** Değeri ekleyip kartı devre dışı bırakıp açınca hata **Kod 31**'e döndü; tam kapatıp açınca düzeldi.
- **Açılış sırası:** önce dock ve kart, sonra dizüstü. OCuLink tak-çalıştır değildir.
- **Tekrar uygulamak gerekir:** NVIDIA *temiz* kurulumundan, kartı Aygıt Yöneticisi'nden kaldırmaktan, Windows'u yeniden kurmaktan ya da **adaptörü başka M.2 yuvasına takmaktan** sonra. Her biri yeni bir cihaz kaydı oluşturur. Betiği tekrar çalıştırmanız yeterli.
- **Grafik modu (MUX):** *Hibrit* kalsın. Dizüstü ekranı dahili grafikten, monitör eGPU'nun kendi çıkışından çalışır.
- **Windows güvenliğini kapatmanız gerekmez.** *Bellek bütünlüğü* ve *Microsoft Savunmasız Sürücü Engelleme Listesi* **açıkken** çalıştığı test makinesinde doğrulandı.
- **Yanıltıcı ipucu:** HP BIOS'u eGPU'ya kendi alt sistem kimliğini (`103C:8C99`) yazıp kilitliyor. Şüpheli görünüyor ama sorun o değil.
- **Geri almak için:** `RM1774520` değerini silip yeniden başlatın.
- **Yük altında kopuyorsa:** önce adaptör ve kablodan şüphelenin; daha kısa (30–50 cm) OCuLink kablosu ya da redriver çipli M.2 adaptörü deneyin. Kabloya çarpmak da kartı bir sonraki açılışa kadar düşürür.

`RM1774520` belgelenmemiş bir ayardır, kullanım sorumluluğu size aittir. İşe yaramayan 10 testin listesi için yukarıdaki *What did not fix it* tablosuna bakın.
