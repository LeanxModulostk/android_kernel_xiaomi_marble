#!/bin/bash

# definición de color
yellow='\033[0;33m'
white='\033[0m'
red='\033[0;31m'
green='\033[0;32m'
blue='\033[0;34m'
purple='\033[0;35m'
cyan='\033[0;36m'

# Función de salida de mensajes en color
color_echo() {
    local color=$1
    shift
    echo -e "${color}$*${white}"
}

# Asegúrese de que el script salga en caso de error
set -e

# --- Mejora clave 1: localizar dinámicamente directorios de scripts ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR" || {
    color_echo "$red" "No se puede cambiar al directorio donde se encuentra el script: $SCRIPT_DIR"
    exit 1
}
color_echo "$green" "directorio de trabajo: $SCRIPT_DIR"

# --- Mejora clave 2: mejora del análisis de parámetros ---
# Manejo de parámetros
TARGET_DEVICE=""
KERNEL_NAME="GlowXXX"
KERNEL_VERSION="v3.9"
FIX_VERSION="1"
USE_KSU=true       # KSU está habilitado de forma predeterminada
CCACHE_ENABLED=true
NO_CLEAN=false
USE_THINLTO=true   # ThinLTO está habilitado de forma predeterminada
MAKE_FLAGS=""

# Resolver el dispositivo de destino
if [ $# -lt 1 ]; then
    color_echo "$red" "Error: no se ha especificado ningún dispositivo de destino"
    color_echo "$yellow" "Uso: $0 <nombre del dispositivo> [opciones]"
    exit 1
fi
TARGET_DEVICE="$1"
shift || true

# Manejar parámetros de opción
while [ $# -gt 0 ]; do
    case "$1" in
        --noccache)
            CCACHE_ENABLED=false
            shift
            ;;
        --noclean)
            NO_CLEAN=true
            shift
            ;;
        --nothinlto)
            USE_THINLTO=false
            shift
            ;;
        --noksu)
            USE_KSU=false
            shift
            ;;
        --)
            shift
            MAKE_FLAGS="$*"
            break
            ;;
        *)
            color_echo "$yellow" "Ignorar opciones desconocidas: $1"
            shift
            ;;
    esac
done

# --- Mejora clave 3: directorio de compilación único ---
BUILD_DIR="../Releases_${TARGET_DEVICE}_${KERNEL_NAME}"
color_echo "$green" "Utilice un directorio de compilación independiente: $BUILD_DIR"

CLANG_PATH=${CLANG_PATH:-$HOME/build_toolchain/clang-r522817/bin}

# Establecer la ruta completa de la herramienta
export CLANG_BIN="$CLANG_PATH/clang"
export CLANGXX_BIN="$CLANG_PATH/clang++"

# Modificar ruta del producto
MAKE_ARGS="O=$BUILD_DIR"

# Información de compilación
MAKE_ARGS+=" KBUILD_BUILD_HOST=Lean"
MAKE_ARGS+=" KBUILD_BUILD_USER=GlowXXX"

# Modificar la configuración de los parámetros de compilación
MAKE_ARGS+=" ARCH=arm64"
MAKE_ARGS+=" SUBARCH=arm64"

# LLVM toolchain - Usar ruta completa
MAKE_ARGS+=" CC=$CLANG_BIN"
MAKE_ARGS+=" LLVM=1"
MAKE_ARGS+=" LLVM_IAS=1"

# Clang triple (Compatible con algunos scripts del kernel)
MAKE_ARGS+=" CLANG_TRIPLE=aarch64-linux-gnu-"

# Establecer la variable de entorno PATH
export PATH="$CLANG_PATH:$PATH"

# set ccache
if $CCACHE_ENABLED; then
    export CCACHE_DIR="${HOME}/.cache/ccache_${TARGET_DEVICE}_build"
    export CC="ccache $CLANG_BIN"
    export CXX="ccache $CLANGXX_BIN"
    export PATH="/usr/lib/ccache:$PATH"
    color_echo "$green" "caché habilitado | directorio de caché: $CCACHE_DIR"
else
    color_echo "$yellow" "Advertencia: ccache está deshabilitado, la velocidad de compilación puede reducirse"
fi


# Compruebe si existe la configuración del dispositivo
if [[ ! -f "$SCRIPT_DIR/arch/arm64/configs/${TARGET_DEVICE}_defconfig" ]]; then
    color_echo "$red" "Error: No se encontró la configuración para el dispositivo de destino [$TARGET_DEVICE]"
    color_echo "$yellow" "Configuraciones de dispositivos disponibles:"
    ls "$SCRIPT_DIR/arch/arm64/configs/"*_defconfig | sed "s/.*\///; s/_defconfig//" | xargs printf "  %s\n"
    exit 1
fi

# Mostrar información ambiental
color_echo "$cyan" "=============================================="
color_echo "$green" "Información de configuración de compilación:"
color_echo "$cyan" "=============================================="
color_echo "$yellow" "dispositivo de destino:    $TARGET_DEVICE"
color_echo "$yellow" "Nombre del kernel:    $KERNEL_NAME"
color_echo "$yellow" "Versión del núcleo:    $KERNEL_VERSION"
color_echo "$yellow" "Versión de reparación:    $FIX_VERSION"
color_echo "$yellow" "KernelSU:    $($USE_KSU && echo "Activado" || echo "Desactivado")"
color_echo "$yellow" "ThinLTO:     $($USE_THINLTO && echo "Activado" || echo "Desactivado")"
color_echo "$yellow" "ccache:      $($CCACHE_ENABLED && echo "Activado" || echo "Desactivado")"
color_echo "$yellow" "limpiar:        $($NO_CLEAN && echo "no implementar" || echo "implementar")"
color_echo "$cyan" "=============================================="

color_echo "$green" "[información de la versión clang]:"
"$CLANG_BIN" --version

# Limpiar el área de trabajo
if ! $NO_CLEAN; then
    color_echo "$yellow" "Limpiar el área de trabajo..."
    rm -rf "$BUILD_DIR"
else
    color_echo "$yellow" "Saltar el paso de limpieza..."
fi

# Agregar fecha a la versión local
LOCAL_VERSION_STR="-GlowXXX"
LOCAL_VERSION_DATE="-${KERNEL_NAME}-${KERNEL_VERSION}-$(date +%y%m%d)${FIX_VERSION}"
touch .scmversion

# Configurar el kernel
color_echo "$green" "Configuración ${TARGET_DEVICE}_defconfig..."
make $MAKE_ARGS "${TARGET_DEVICE}_defconfig"

# Establecer versión local
./scripts/config --file "$BUILD_DIR/.config" --set-str CONFIG_LOCALVERSION "$LOCAL_VERSION_DATE"

# Activar/desactivar la configuración basada en KSU
if $USE_KSU; then
    color_echo "$green" "permitir KernelSU..."
    ./scripts/config --file "$BUILD_DIR/.config" \
        -e KSU \
        -e KSU_MANUAL_HOOK \
        -e KSU_SUSFS \
        -d KSU_SUSFS_SUS_SU \
        -e KSU_MULTI_MANAGER_SUPPORT 


else
    color_echo "$yellow" "Desactivar KernelSU..."
    ./scripts/config --file "$BUILD_DIR/.config" \
        -d KSU \
        -d KSU_MANUAL_HOOK \
        -d KSU_SUSFS \
        -d KSU_MULTI_MANAGER_SUPPORT 
fi

# Manejo de la configuración LTO
if $USE_THINLTO; then
    color_echo "$green" "Activar ThinLTO..."
    ./scripts/config --file "$BUILD_DIR/.config" -e LTO_CLANG -e THINLTO
else
    color_echo "$yellow" "Desactivar ThinLTO..."
    ./scripts/config --file "$BUILD_DIR/.config" -e LTO_CLANG -d THINLTO
fi

make $MAKE_ARGS olddefconfig

# Hora de inicio de grabación
START_TIME=$(date +%s)
NUM_JOBS=$(nproc --all)

# compilar kernel
color_echo "$green" "Comience a compilar el kernel (usando subprocesos $NUM_JOBS)..."
make $MAKE_ARGS -j$(nproc --all) $MAKE_FLAGS

# Comprueba los resultados de la compilación.
IMAGE_PATH="$BUILD_DIR/arch/arm64/boot/Image"
if [[ ! -f "$IMAGE_PATH" ]]; then
    color_echo "$red" "Error: No se encontró la imagen del kernel [$IMAGE_PATH], la compilación falló"
    exit 1
fi

# Calcular el tiempo de compilación
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
MINUTES=$((DURATION / 60))
SECONDS=$((DURATION % 60))

color_echo "$green" "¡Compilación exitosa! Tiempo necesario: ${MINUTES} minutos ${SECONDS} segundos"

ANY_KERNEL_DIR="$SCRIPT_DIR/anykernel"

cp "$IMAGE_PATH" "$ANY_KERNEL_DIR"

# Crear nombre de archivo ZIP
KSU_STR=$($USE_KSU && echo "Sukisu-Ultra" || echo "NoKSU")
ZIP_NAME="${TARGET_DEVICE}_${KERNEL_NAME}-${KERNEL_VERSION}_${KSU_STR}_$(date +%y%m%d)${FIX_VERSION}.zip"

color_echo "$green" "Crear paquete flash: $ZIP_NAME"
(cd "$ANY_KERNEL_DIR" && zip -r9 "$ZIP_NAME" ./* -x .git .gitignore out/ ./*.zip)

mv "$ANY_KERNEL_DIR/$ZIP_NAME" "$BUILD_DIR/"

color_echo "$green" "¡Completo! El paquete flash se ha guardado en: [$BUILD_DIR/$ZIP_NAME]"

color_echo "$green" "ALL DONE"

#gracias AviderMin :)