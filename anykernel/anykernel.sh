### AnyKernel3 Ramdisk Mod Script
## osm0sis @ xda-developers

### AnyKernel setup
# global properties
properties() { '
kernel.string=GlowXXX Kernel By Lean
do.devicecheck=1
do.modules=0
do.systemless=1
do.cleanup=1
do.cleanuponabort=0
device.name1=marble
device.name2=marblein
device.name3=
device.name4=
device.name5=
supported.versions=
supported.patchlevels=
supported.vendorpatchlevels=
'; } # end properties


### AnyKernel install

## boot shell variables
block=boot
is_slot_device=1
ramdisk_compression=auto
patch_vbmeta_flag=auto
no_magisk_check=true

# import functions/variables and setup patching - see for reference (DO NOT REMOVE)
. tools/ak3-core.sh

split_boot # skip ramdisk unpack

########## FLASH BOOT & VENDOR_DLKM START ##########

KEYCODE_UP=42
KEYCODE_DOWN=41

extract_erofs() {
	local img_file=$1
	local out_dir=$2

	${bin}/extract.erofs -i "$img_file" -x -T8 -o "$out_dir" &> /dev/null
}

mkfs_erofs() {
	local work_dir=$1
	local out_file=$2
	local partition_name

	partition_name=$(basename "$work_dir")

	${bin}/mkfs.erofs \
		--mount-point "/${partition_name}" \
		--fs-config-file "${work_dir}/../config/${partition_name}_fs_config" \
		--file-contexts  "${work_dir}/../config/${partition_name}_file_contexts" \
		-z lz4hc \
		"$out_file" "$work_dir"
}

is_mounted() { mount | grep -q " $1 "; }


get_keycheck_result() {
	# Comportamiento por defecto:
	# - presionar Vol+: retorna verdadero (0)
	# - presionar Vol-: retorna falso (1)

	local rc_1 rc_2

	while true; do
		# La primera ejecución responde al evento de pulsar el botón,
		# la segunda ejecución responde al evento de soltar el botón.
		${bin}/keycheck; rc_1=$?
		${bin}/keycheck; rc_2=$?
		[ "$rc_1" == "$rc_2" ] || continue
		case "$rc_2" in
			"$KEYCODE_UP") return 0;;
			"$KEYCODE_DOWN") return 1;;
		esac
	done
}

keycode_select() {
	local r_keycode

	ui_print " "
	while [ $# != 0 ]; do
		ui_print "# $1"
		shift
	done
	ui_print "#"
	ui_print "# Vol+ = Sí, Vol- = No."
	ui_print "# Por favor, presiona un botón..."
	get_keycheck_result
	r_keycode=$?
	ui_print "#"
	if [ "$r_keycode" -eq "0" ]; then
		ui_print "- Has seleccionado: Sí."
	else
		ui_print "- Has seleccionado: No."
	fi
	ui_print " "
	return $r_keycode
}

get_size() {
	local _path=$1
	local _size

	if [ -d "$_path" ]; then
		du -bs $_path | awk '{print $1}'
		return
	fi
	if [ -b "$_path" ]; then
		_size=$(blockdev --getsize64 $_path) && {
			echo $_size
			return
		}
	fi
	wc -c < $_path
}

bytes_to_mb() {
	echo $1 | awk '{printf "%.1fM", $1 / 1024 / 1024}'
}

check_super_device_size() {
	# Verificar tamaño del dispositivo super
	local block_device_size block_device_size_lp

	block_device_size=$(get_size /dev/block/by-name/super) || \
		abort "! ¡Error al leer el tamaño de la partición super (vía blockdev)!"
	block_device_size_lp=$(${bin}/lpdump 2>/dev/null | grep -m1 -E 'Size: [[:digit:]]+ bytes$' | awk '{print $2}') || \
		abort "! ¡Error al leer el tamaño de la partición super (vía lpdump)!"
	ui_print "- Tamaño de la partición super:"
	ui_print "  - Leído por blockdev: $block_device_size"
	ui_print "  - Leído por lpdump: $block_device_size_lp"
	[ "$block_device_size" == "9663676416" ] && [ "$block_device_size_lp" == "9663676416" ] || \
		abort "! ¡El tamaño de la partición super no coincide!"
}

# copy_gpu_pwrlevels_conf <archivo dtb original> <nuevo archivo dtb>
copy_gpu_pwrlevels_conf() {
	local orig_dtb=$1
	local new_dtb=$2
	local KGSL_NODE="/soc/qcom,kgsl-3d0@3d00000"
	local PWRLEVELS_NODE="${KGSL_NODE}/qcom,gpu-pwrlevels"
	local node reg gpu_freq bus_freq bus_min bus_max level cx_level acd_level initial_pwrlevel

	# Limpiar la configuración de frecuencia y voltaje de la GPU de new_dtb
	for node in $(${bin}/fdtget "$new_dtb" "$PWRLEVELS_NODE" -l); do
		${bin}/fdtput "$new_dtb" -r "/soc/qcom,kgsl-3d0@3d00000/qcom,gpu-pwrlevels/${node}"
	done

	for node in $(${bin}/fdtget "$orig_dtb" /soc/qcom,kgsl-3d0@3d00000/qcom,gpu-pwrlevels -l | sort -r); do
		# Leer
		      reg=$(${bin}/fdtget "$orig_dtb" "${PWRLEVELS_NODE}/${node}" "reg" -tu)
		 gpu_freq=$(${bin}/fdtget "$orig_dtb" "${PWRLEVELS_NODE}/${node}" "qcom,gpu-freq" -tu)
		 bus_freq=$(${bin}/fdtget "$orig_dtb" "${PWRLEVELS_NODE}/${node}" "qcom,bus-freq" -tu)
		  bus_min=$(${bin}/fdtget "$orig_dtb" "${PWRLEVELS_NODE}/${node}" "qcom,bus-min" -tu)
		  bus_max=$(${bin}/fdtget "$orig_dtb" "${PWRLEVELS_NODE}/${node}" "qcom,bus-max" -tu)
		    level=$(${bin}/fdtget "$orig_dtb" "${PWRLEVELS_NODE}/${node}" "qcom,level" -tu)
		 cx_level=$(${bin}/fdtget "$orig_dtb" "${PWRLEVELS_NODE}/${node}" "qcom,cx-level" -tu)
		acd_level=$(${bin}/fdtget "$orig_dtb" "${PWRLEVELS_NODE}/${node}" "qcom,acd-level" -tx)

		# Escribir
		${bin}/fdtput "$new_dtb" -c "${PWRLEVELS_NODE}/${node}"
		${bin}/fdtput "$new_dtb" "${PWRLEVELS_NODE}/${node}" "qcom,cx-level"  "$cx_level" -tu
		${bin}/fdtput "$new_dtb" "${PWRLEVELS_NODE}/${node}" "qcom,acd-level" "$acd_level" -tx
		${bin}/fdtput "$new_dtb" "${PWRLEVELS_NODE}/${node}" "qcom,bus-max"   "$bus_max" -tu
		${bin}/fdtput "$new_dtb" "${PWRLEVELS_NODE}/${node}" "qcom,bus-min"   "$bus_min" -tu
		${bin}/fdtput "$new_dtb" "${PWRLEVELS_NODE}/${node}" "qcom,bus-freq"  "$bus_freq" -tu
		${bin}/fdtput "$new_dtb" "${PWRLEVELS_NODE}/${node}" "qcom,level"     "$level" -tu
		${bin}/fdtput "$new_dtb" "${PWRLEVELS_NODE}/${node}" "qcom,gpu-freq"  "$gpu_freq" -tu
		${bin}/fdtput "$new_dtb" "${PWRLEVELS_NODE}/${node}" "reg" "$reg" -tu
	done

	initial_pwrlevel=$(${bin}/fdtget "$orig_dtb" "$KGSL_NODE" "qcom,initial-pwrlevel" -tu)
	${bin}/fdtput "$new_dtb" "$KGSL_NODE" "qcom,initial-pwrlevel" "$initial_pwrlevel" -tu
}

random_strings() {
	local len=$1

	cat /dev/urandom | tr -dc 'a-zA-Z' | head -c $len
}

# Verificar firmware
if strings /dev/block/bootdevice/by-name/xbl_config${slot} | grep -q 'led_blink'; then
	ui_print "¡Firmware HyperOS detectado!"
	is_hyperos_fw=true
	is_hyperos_fw_with_new_adsp2=false
	if is_mounted /vendor/firmware_mnt && [ -d /vendor/firmware_mnt/image ]; then
		modem_mount_path=/vendor/firmware_mnt
	else
		for blk in /dev/block/by-name/modem${slot} /dev/block/bootdevice/by-name/modem${slot} "$(readlink /dev/block/bootdevice/by-name/modem${slot})"; do
			if mount | grep -qE "^${blk} "; then
				modem_mount_path=$(mount | grep -E "^${blk} " | awk '{print $3}')
				break
			fi
		done
		if [ -z "$modem_mount_path" ]; then
			mkdir ${home}/_modem_mnt
			mount /dev/block/bootdevice/by-name/modem${slot} ${home}/_modem_mnt -o ro || \
				abort "! ¡No se puede montar la partición modem!"
			modem_mount_path=${home}/_modem_mnt
		fi
	fi

	if strings "${modem_mount_path}/image/adsp2.b18" | grep -q 'audiostatus'; then
		ui_print "¡Nueva versión de firmware adsp2 detectada!"
		is_hyperos_fw_with_new_adsp2=true
	fi

	if [ -d "${home}/_modem_mnt" ]; then
		umount ${home}/_modem_mnt
		rmdir ${home}/_modem_mnt
	fi

	unset modem_mount_path
else
	ui_print "¡Firmware MIUI14 detectado!"
	is_hyperos_fw=false
fi

# Preparar imágenes de particiones no modificadas
mkdir -p ${home}/_orig
cp ${home}/boot.img ${home}/_orig/boot.img

# Verificar estado del snapshot
# Detalles técnicos: https://blog.xzr.moe/archives/30/
${bin}/snapshotupdater_static dump &>/dev/null
rc=$?
if [ "$rc" != 0 ]; then
	ui_print " "
	ui_print "No se puede leer el estado del snapshot vía snapshotupdater_static rc=$rc."
	if ${BOOTMODE}; then
		ui_print "Intenta instalar con otra app."
		ui_print "Recomendado KernelFlasher:"
		ui_print "  https://github.com/capntrips/KernelFlasher/releases"
	fi
	abort "Abortando..."
fi
snapshot_status=$(${bin}/snapshotupdater_static dump 2>/dev/null | grep '^Update state:' | awk '{print $3}')
ui_print "Estado actual del snapshot: $snapshot_status"
if [ "$snapshot_status" != "none" ]; then
	ui_print " "
	ui_print "Parece que acabas de actualizar la rom."
	ui_print "Por favor, usa primero la función \"Fusionar snapshot\" en el menú avanzado de TWRP"
	ui_print "para completar la fusión del snapshot inmediatamente."
	abort "Abortando..."
fi
unset rc snapshot_status

# Verificar tipo de rom
is_miui_rom=false
is_aospa_rom=false
is_oss_kernel_rom=false
if [ -f /system/framework/MiuiBooster.jar ] && keycode_select "¿Tu rom actual es HyperOS? (Supongo que sí)"; then
	is_miui_rom=true
elif cat /system/build.prop | grep -qi 'aospa' && keycode_select "¿Tu rom actual es AOSPA? (Supongo que sí)"; then
	is_aospa_rom=true
elif keycode_select "¿Tu rom está basada en kernel OSS?"; then
	is_oss_kernel_rom=true
fi

strings ${home}/Image 2>/dev/null | grep -E -m1 'Linux version.*#' > ${home}/vertmp

# Verificar estado de la partición vendor_dlkm
[ -d /vendor_dlkm ] || mkdir /vendor_dlkm
is_mounted /vendor_dlkm || \
	mount /vendor_dlkm -o ro || mount /dev/block/mapper/vendor_dlkm${slot} /vendor_dlkm -o ro || \
		abort "! No se puede montar /vendor_dlkm"

do_backup_flag=false
if [ ! -f /vendor_dlkm/lib/modules/vertmp ]; then
	do_backup_flag=true
fi
$BOOTMODE || umount /vendor_dlkm


# Solucionar incapacidad de montar imagen como lectura-escritura en recovery
$BOOTMODE || setenforce 0

ui_print " "
ui_print "- Desempaquetando módulos del kernel..."
if ${is_hyperos_fw}; then
	modules_pkg=${home}/_modules_hyperos.7z
else
	modules_pkg=${home}/_modules_miui.7z
fi
[ -f $modules_pkg ] || abort "! ¡No se encuentra ${modules_pkg}!"
${bin}/7za x $modules_pkg -o${home}/ && [ -d ${home}/_vendor_boot_modules ] && [ -d ${home}/_vendor_dlkm_modules ] || \
	abort "! ¡No se puede desempaquetar ${modules_pkg}!"
if ${is_hyperos_fw} && ${is_hyperos_fw_with_new_adsp2}; then
	cp -f ${home}/_alt/NEW-qti_battery_charger_main.ko ${home}/_vendor_dlkm_modules/qti_battery_charger_main.ko
	cp -f ${home}/_alt/NEW-qti_battery_charger_main.ko ${home}/_vendor_boot_modules/qti_battery_charger_main.ko
fi
unset modules_pkg

vendor_dlkm_modules_options_file=${home}/_vendor_dlkm_modules/modules.options
[ -f $vendor_dlkm_modules_options_file ] || touch $vendor_dlkm_modules_options_file

# xiaomi_touch.ko
if ${is_hyperos_fw} && [ -f /vendor/bin/hw/vendor.lineage.touch@* ]; then
	ui_print " "
	ui_print "- Lineage OSS xiaomi touch HAL detectado."
	ui_print "- Usando controlador táctil alternativo."
	cp -f ${home}/_alt/xiaomi_touch_los/* ${home}/_vendor_dlkm_modules/
	sed -i \
	    's/\/vendor\/lib\/modules\/xiaomi_touch\.ko:/\/vendor\/lib\/modules\/xiaomi_touch\.ko:\ \/vendor\/lib\/modules\/panel_event_notifier\.ko/g' \
	    ${home}/_vendor_dlkm_modules/modules.dep
fi

# goodix_core.ko
if keycode_select \
    "¿Habilitar siempre la tasa de muestreo táctil de 360HZ?" \
    " " \
    "Nota:" \
    "Habilitar siempre 360HZ no mejorará tu experiencia" \
    "diaria, y puede aumentar el consumo de batería." \
	" "; then
	echo "options goodix_core force_high_report_rate=y" >> $vendor_dlkm_modules_options_file
fi

# qti_battery_charger_main.ko
if ${is_hyperos_fw}; then
	modname_qti_battery_charger=qti_battery_charger_main
else
	modname_qti_battery_charger=qti_battery_charger
fi

qti_battery_charger_mod_options=""
if keycode_select \
    "¿Mostrar porcentaje de batería más realista?" \
    " " \
    "Nota:" \
    "Esto podría causar que el dispositivo sea difícil de cargar al 100%." \
    " "; then
	qti_battery_charger_mod_options="${qti_battery_charger_mod_options} report_real_capacity=y"
fi

do_fix_battery_usage=false
if ${is_fixed_qbc_driver} || ${is_oss_kernel_rom}; then
	do_fix_battery_usage=true
elif ${is_miui_rom} || ${is_aospa_rom}; then
	do_fix_battery_usage=false
elif keycode_select \
    "¿Reparar datos anómalos del uso de la batería?" \
    " " \
    "Nota:" \
    "Si encuentras que los datos de uso de la batería en" \
    "Configuración del sistema no se muestran normalmente, elige Sí." \
	" "; then
	do_fix_battery_usage=true
fi
if ${do_fix_battery_usage}; then
	qti_battery_charger_mod_options="${qti_battery_charger_mod_options} fix_battery_usage=y"
fi
unset do_fix_battery_usage

if [ -n "${qti_battery_charger_mod_options}" ]; then
	qti_battery_charger_mod_options=$(echo "$qti_battery_charger_mod_options" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
	echo "options qti_battery_charger_main ${qti_battery_charger_mod_options}" >> $vendor_dlkm_modules_options_file
fi
unset modname_qti_battery_charger qti_battery_charger_mod_options

# Modo alternativo de botones de auriculares con cable
use_wired_btn_altmode=false
if ${is_miui_rom}; then
	use_wired_btn_altmode=false
elif ${is_oss_kernel_rom} || ${is_aospa_rom}; then
	use_wired_btn_altmode=true
elif keycode_select \
    "¿Usar modo alternativo para botones de auriculares con cable?" \
    " " \
    "Nota:" \
    "Si encuentras que los botones de volumen de los auriculares con cable no funcionan bien, elige Sí." \
    "Si estás usando una rom MIUI/HyperOS, elige No." \
    " "; then
	use_wired_btn_altmode=true
fi
if ${use_wired_btn_altmode}; then
	echo "options machine_dlkm waipio_wired_btn_altmode=y" >> $vendor_dlkm_modules_options_file
fi
unset use_wired_btn_altmode

# msm_drm.ko OSS
if ${is_hyperos_fw}; then
	use_oss_msm_drm=false
	if ${is_oss_kernel_rom} || ${is_aospa_rom} || [ -f /vendor/bin/sensor-notifier ]; then
		use_oss_msm_drm=true
	elif ! ${is_miui_rom}; then  # For roms ported from other OS
		use_oss_msm_drm=false
	elif keycode_select \
	    "¿Usar controlador de pantalla de código abierto?" \
	    " " \
	    "Nota:" \
	    "Si no sabes qué significa esto, elige No."; then
		use_oss_msm_drm=true
	fi
	if ${use_oss_msm_drm}; then
		if [ -f /vendor/etc/displayconfig/display_id_4630946370515662721.xml ] || [ -f /vendor/etc/displayconfig/display_id_4630946480857061761.xml ]; then
			# https://github.com/cupid-development/android_device_xiaomi_marble/commit/eee64379280d5bc680e91371679d788b63fe5039
			cp -f ${home}/_alt/OSS-msm_drm-2.ko ${home}/_vendor_dlkm_modules/msm_drm.ko
		else
			cp -f ${home}/_alt/OSS-msm_drm.ko ${home}/_vendor_dlkm_modules/msm_drm.ko
		fi
	fi
	unset use_oss_msm_drm
fi

# ir-spi.ko OSS
if ${is_hyperos_fw}; then
	use_oss_ir_driver=false
	if ${is_miui_rom}; then
		use_oss_ir_driver=false
	elif [ -f /vendor/bin/hw/android.hardware.ir@* ]; then
		ui_print " " "- HAL IR stock de Xiaomi detectado. Usando controlador IR stock."
		use_oss_ir_driver=false
	elif [ -f /vendor/bin/hw/android.hardware.ir-service.xiaomi ]; then
		ui_print " " "- HAL IR OSS de Lineage detectado. Usando controlador IR OSS."
		use_oss_ir_driver=true
	elif keycode_select \
	    "Usar controlador infrarrojo de código abierto?" \
	    " " \
	    "Nota:" \
	    "Si estás usando una rom AOSP y encuentras que el control remoto" \
	    "infrarrojo no funciona bien, elige Sí." \
	    "Si estás usando una rom MIUI/HyperOS, elige No."; then
		use_oss_ir_driver=true
	fi
	if ${use_oss_ir_driver}; then
		cp -f ${home}/_alt/OSS-ir-spi.ko ${home}/_vendor_dlkm_modules/ir-spi.ko
	fi
	unset use_oss_ir_driver
fi

# zram.ko & zsmalloc.ko OSS
if ${is_miui_rom}; then
	if ! keycode_select \
	    "¿Usar módulos del kernel ZRAM de código abierto?" \
	    " " \
	    "Nota:" \
	    "Usar los módulos del kernel ZRAM de código abierto significa que renunciarás a las" \
	    "optimizaciones especiales de Xiaomi para ZRAM en MIUI/HyperOS." \
	    " " \
	    "Si no sabes qué significa esto, elige No." \
		" "; then
		cp -f ${home}/_alt/MI-zram.ko ${home}/_vendor_dlkm_modules/zram.ko
		cp -f ${home}/_alt/MI-zsmalloc.ko ${home}/_vendor_dlkm_modules/zsmalloc.ko
	fi
fi

unset vendor_dlkm_modules_options_file

# Disfrazar el modelo de GPU como Adreno730v3
disguised_adreno730=false
if keycode_select \
    "¿Disfrazar el modelo de GPU como Adreno730?" \
    " " \
    "Nota:" \
    "La GPU del Snapdragon 8+ Gen1 es precisamente Adreno730." \
    "Disfrazar el modelo de GPU como Adreno730 quizás pueda" \
    "desbloquear mejores gráficos o tasa de fotogramas en" \
    "algunos juegos móviles," \
    "pero se desconocen los efectos secundarios." \
	" "; then
	disguised_adreno730=true
fi

# No cargar algunos módulos especiales de Xiaomi en ROMs AOSP
if ! ${is_miui_rom}; then
	# Módulos relacionados con millet
	for module_name in millet_core millet_binder millet_hs millet_oem_cgroup millet_pkg millet_sig binder_gki; do
		echo "blocklist $module_name" >> ${home}/_vendor_dlkm_modules/modules.blocklist
	done
	# Otros
	for module_name in extend_reclaim mi_freqwdg mi_memory perf_helper; do
		echo "blocklist $module_name" >> ${home}/_vendor_boot_modules/modules.blocklist
	done
	for module_name in binder_prio mi_freqwdg miicmpfilter perf_helper; do
		echo "blocklist $module_name" >> ${home}/_vendor_dlkm_modules/modules.blocklist
	done
fi

if ! keycode_select \
    "Esta es la última opción." \
    " " \
    "Selecciona Sí para comenzar la instalación formal." \
    "Selecciona No para cancelar la instalación." \
	" "; then
	abort "Cancelado por el usuario."
fi

ui_print " "
if true; then  # No quiero ajustar la sangría del bloque de código siguiente, así que lo dejo como está.
	do_check_super_device_size=false

	# Volcar imagen de la partición vendor_dlkm
	dd if=/dev/block/mapper/vendor_dlkm${slot} of=${home}/vendor_dlkm.img
	cp ${home}/vendor_dlkm.img ${home}/_orig/vendor_dlkm.img
	vendor_dlkm_block_size=$(get_size /dev/block/mapper/vendor_dlkm${slot})

	# Hacer copia de seguridad del kernel y de la imagen vendor_dlkm
	if ${do_backup_flag}; then
		ui_print "- Parece que es tu primera vez instalando GlowX Kernel."

		if keycode_select "¿Hacer copia de seguridad del kernel actual?"; then
			ui_print "- Haciendo copia de seguridad de kernel, vendor_boot, vendor_dlkm"
			ui_print "  y de la partición dtbo..."

			backup_package=/sdcard/GlowX-restore-kernel-$(file_getprop /system/build.prop ro.build.version.incremental)-$(date +"%Y%m%d-%H%M%S").zip

			${bin}/7za a -tzip -bd $backup_package \
				${home}/META-INF ${bin} ${home}/LICENSE ${home}/_restore_anykernel.sh \
				${split_img}/kernel \
				${home}/vendor_dlkm.img \
				/dev/block/bootdevice/by-name/vendor_boot${slot} \
				/dev/block/bootdevice/by-name/dtbo${slot}
			${bin}/7za rn -bd $backup_package kernel Image
			${bin}/7za rn -bd $backup_package _restore_anykernel.sh anykernel.sh
			${bin}/7za rn -bd $backup_package vendor_boot${slot} vendor_boot.img
			${bin}/7za rn -bd $backup_package dtbo${slot} dtbo.img
			sync

			ui_print " "
			ui_print "- El kernel, vendor_boot, vendor_dlkm"
			ui_print "  y dtbo actuales han sido respaldados en:"
			ui_print "  $backup_package"
			ui_print "- Si encuentras problemas o quieres restaurar el kernel original,"
			ui_print "  flashealo desde TWRP o alguna aplicación."
			ui_print " "
			touch ${home}/do_backup_flag

			if ! $BOOTMODE && [ ! -d /twres ]; then
				ui_print "============================================================"
				ui_print "! Advertencia: Por favor, transfiere el archivo de respaldo recién generado a"
				ui_print "! otro dispositivo via ADB, ya que se perderá después del reinicio!"
				ui_print "============================================================"
				ui_print " "
				sleep 3
			fi

			unset backup_package
		fi
	fi

	ui_print "- Desempaquetando la partición /vendor_dlkm..."
	extract_vendor_dlkm_dir=${home}/_extract_vendor_dlkm_$(random_strings 3)
	mkdir -p $extract_vendor_dlkm_dir
	vendor_dlkm_is_ext4=false
	extract_erofs ${home}/vendor_dlkm.img $extract_vendor_dlkm_dir || vendor_dlkm_is_ext4=true
	sync

	if ${vendor_dlkm_is_ext4}; then
		ui_print "- /vendor_dlkm parece ser un sistema de archivos ext4."
		mount ${home}/vendor_dlkm.img $extract_vendor_dlkm_dir -o ro -t ext4 || \
			abort "! Sistema de archivos no soportado!"
		vendor_dlkm_full_space=$(df -B1 | grep -E -m1 "$(basename $extract_vendor_dlkm_dir)\$" | awk '{print $2}')
		vendor_dlkm_used_space=$(df -B1 | grep -E -m1 "$(basename $extract_vendor_dlkm_dir)\$" | awk '{print $3}')
		vendor_dlkm_free_space=$(df -B1 | grep -E -m1 "$(basename $extract_vendor_dlkm_dir)\$" | awk '{print $4}')
		vendor_dlkm_stock_modules_size=$(get_size ${extract_vendor_dlkm_dir}/lib/modules)
		ui_print "- Espacio de la partición /vendor_dlkm:"
		ui_print "  - Espacio total: $(bytes_to_mb $vendor_dlkm_full_space)"
		ui_print "  - Espacio usado: $(bytes_to_mb $vendor_dlkm_used_space)"
		ui_print "  - Espacio libre: $(bytes_to_mb $vendor_dlkm_free_space)"
		umount $extract_vendor_dlkm_dir

		vendor_dlkm_new_modules_size=$(get_size ${home}/_vendor_dlkm_modules)
		vendor_dlkm_need_size=$((vendor_dlkm_used_space - vendor_dlkm_stock_modules_size + vendor_dlkm_new_modules_size + 10*1024*1024))
		if [ "$vendor_dlkm_need_size" -ge "$vendor_dlkm_full_space" ]; then
			# Redimensionar imagen vendor_dlkm
			ui_print "- ¡La partición /vendor_dlkm no tiene suficiente espacio libre!"
			ui_print "- Intentando expandir..."

			${bin}/e2fsck -f -y ${home}/vendor_dlkm.img
			vendor_dlkm_resized_size=$(echo $vendor_dlkm_need_size | awk '{printf "%dM", ($1 / 1024 / 1024 + 1)}')
			${bin}/resize2fs ${home}/vendor_dlkm.img $vendor_dlkm_resized_size || \
				abort "! ¡Error al expandir la imagen vendor_dlkm!"
			ui_print "- Tamaño de la imagen vendor_dlkm.img después de la expansión: ${vendor_dlkm_resized_size}."
			# e2fsck de nuevo
			${bin}/e2fsck -f -y ${home}/vendor_dlkm.img

			do_check_super_device_size=true
			unset vendor_dlkm_resized_size
		else
			ui_print "- La partición /vendor_dlkm tiene suficiente espacio libre."
		fi

		ui_print "- Intentando montar la imagen vendor_dlkm como lectura/escritura..."
		mount ${home}/vendor_dlkm.img $extract_vendor_dlkm_dir -o rw -t ext4 || \
			abort "! ¡No se pudo montar la imagen vendor_dlkm como lectura/escritura!"

		unset vendor_dlkm_full_space vendor_dlkm_used_space vendor_dlkm_free_space vendor_dlkm_stock_modules_size vendor_dlkm_new_modules_size vendor_dlkm_need_size
		extract_vendor_dlkm_modules_dir=${extract_vendor_dlkm_dir}/lib/modules
	else
		extract_vendor_dlkm_modules_dir=${extract_vendor_dlkm_dir}/vendor_dlkm/lib/modules
	fi

	ui_print "- Actualizando la imagen /vendor_dlkm..."
	rm -f ${extract_vendor_dlkm_modules_dir}/*
	cp ${home}/_vendor_dlkm_modules/* ${extract_vendor_dlkm_modules_dir}/ || \
		abort "! ¡Error al actualizar los módulos del kernel! ¿No hay suficiente espacio libre?"
	cp ${home}/vertmp ${extract_vendor_dlkm_modules_dir}/vertmp
	sync

	if ${vendor_dlkm_is_ext4}; then
		set_perm 0 0 0644 ${extract_vendor_dlkm_modules_dir}/*
		chcon u:object_r:vendor_file:s0 ${extract_vendor_dlkm_modules_dir}/*
		umount $extract_vendor_dlkm_dir
	else
		for f in "${extract_vendor_dlkm_modules_dir}"/*; do
			echo "vendor_dlkm/lib/modules/$(basename $f) 0 0 0644" >> ${extract_vendor_dlkm_dir}/config/vendor_dlkm_fs_config
		done
		echo '/vendor_dlkm/lib/modules/.+ u:object_r:vendor_file:s0' >> ${extract_vendor_dlkm_dir}/config/vendor_dlkm_file_contexts
		ui_print "- Empaquetando la imagen /vendor_dlkm..."
		rm -f ${home}/vendor_dlkm.img
		mkfs_erofs ${extract_vendor_dlkm_dir}/vendor_dlkm ${home}/vendor_dlkm.img || \
			abort "! ¡Error al empaquetar la imagen /vendor_dlkm!"
		rm -rf ${extract_vendor_dlkm_dir}

		if [ "$(get_size ${home}/vendor_dlkm.img)" -gt "$vendor_dlkm_block_size" ]; then
			do_check_super_device_size=true
		else
			# Llenar el archivo de imagen erofs al mismo tamaño que la partición vendor_dlkm
			truncate -c -s $vendor_dlkm_block_size ${home}/vendor_dlkm.img
		fi
	fi

	if ${do_check_super_device_size}; then
		ui_print " "
		ui_print "- El tamaño del archivo de imagen generado es mayor que el tamaño de la partición."
		ui_print "- Es necesario verificar la partición super..."
		check_super_device_size  # Si la verificación aquí falla, se abortará directamente.
		ui_print "- ¡Aprobado!"
	fi

	unset do_check_super_device_size vendor_dlkm_block_size vendor_dlkm_is_ext4 extract_vendor_dlkm_dir extract_vendor_dlkm_modules_dir
fi

unset do_backup_flag

flash_boot # omitir reempaquetado de ramdisk
flash_generic vendor_dlkm

########## FIN DE FLASHEO BOOT & VENDOR_DLKM ##########

# Eliminar archivos no necesarios para evitar flashearlos nuevamente.
rm ${home}/Image
rm ${home}/boot.img
rm ${home}/boot-new.img
rm ${home}/vendor_dlkm.img

unset magisk_patched
rm ${home}/magisk_patched

touch ${home}/rollback_if_abort_flag

########## INICIO DE FLASHEO VENDOR_BOOT ##########

## Variables de shell para vendor_boot
block=vendor_boot
is_slot_device=1
ramdisk_compression=auto
patch_vbmeta_flag=auto
no_magisk_check=true

# reset para parcheo de vendor_boot
reset_ak

# Intentar corregir el tamaño de vendor_ramdisk y la información de la tabla de entradas de vendor_ramdisk dañada por versiones antiguas de magiskboot.
${bin}/vendor_boot_fix "$block"
case $? in
	0) ui_print " " "- ¡Partición vendor_boot reparada con éxito!";;
	2) ;;  # La partición vendor_boot es normal y no necesita reparación.
	*) abort "! ¡No se puede reparar la partición vendor_boot dañada!";;
esac

# Instalación de vendor_boot
dump_boot

vendor_boot_modules_dir=${ramdisk}/lib/modules
rm ${vendor_boot_modules_dir}/*
cp ${home}/_vendor_boot_modules/* ${vendor_boot_modules_dir}/
set_perm 0 0 0644 ${vendor_boot_modules_dir}/*

${bin}/7za x ${home}/_dtb.7z -o${home}/ || abort "! ¡No se puede descomprimir _dtb.7z!"

if ${is_oss_kernel_rom}; then
	mv ${home}/dtbo-1.img ${home}/dtbo.img
	rm ${home}/dtbo-0.img
else
	mv ${home}/dtbo-0.img ${home}/dtbo.img
	rm ${home}/dtbo-1.img
fi

mkdir ${home}/_dtbs
cp ${split_img}/dtb ${home}/_dtbs/dtb
dtb_img_splitted=$(${bin}/dtp -i ${home}/_dtbs/dtb | awk '{print $NF}') || abort "! ¡Error al dividir el archivo dtb!"
ukee_dtb=
for dtb_file in $dtb_img_splitted; do
	if [ "$(${bin}/fdtget $dtb_file / model -ts)" == "Qualcomm Technologies, Inc. Ukee SoC" ]; then
		ukee_dtb="$dtb_file"
		break
	fi
done
[ -z "$ukee_dtb" ] && abort "! ¡No se puede encontrar el archivo dtb de Ukee!"

if ${disguised_adreno730}; then
	${bin}/fdtput ${home}/dtb "/soc/qcom,kgsl-3d0@3d00000" "qcom,gpu-model" "Adreno730v3" -ts
fi
unset disguised_adreno730

# Copiar la configuración de frecuencia y voltaje de la GPU del dtb antiguo al nuevo dtb
if [ "$(sha1 $ukee_dtb)" != "$(sha1 ${home}/dtb)" ]; then
	copy_gpu_pwrlevels_conf "$ukee_dtb" ${home}/dtb
	sync
fi

rm -rf ${home}/_dtbs

unset dtb_img_splitted ukee_dtb

write_boot  # Dado que dtbo.img existe en ${home}, la partición dtbo también se flasheará en este momento

########## FIN DE FLASHEO VENDOR_BOOT ##########

unset is_hyperos_fw is_miui_rom is_aospa_rom is_oss_kernel_rom is_hyperos_fw_with_new_adsp2

# Parchear vbmeta
ui_print " "
for vbmeta_blk in /dev/block/by-name/vbmeta*; do
	ui_print "- Parcheando $(basename $vbmeta_blk) ..."
	${bin}/vbmeta-disable-verification $vbmeta_blk || {
		ui_print "! ¡No se puede aplicar parche a ${vbmeta_blk}!"
		ui_print "- Si el dispositivo no arranca después de completar la instalación,"
		ui_print "  deshabilite AVB manualmente en TWRP."
	}
done

ui_print " "
ui_print "SourceCodeBase & FlashScript"
ui_print "Gracias @Pzqqt & AviderMin"

## fin de la instalación del boot