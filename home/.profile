export TERMINAL=alacritty
export BRAVE_FLAGS="--password-store=gnome"
export BROWSER=firefox

# Quantum acceleration
export PICOM_VSYNC=true
export PICOM_BACKEND="glx"
export LIBGL_ALWAYS_INDIRECT=0
export MESA_GL_VERSION_OVERRIDE=4.5
export MESA_GLSL_VERSION_OVERRIDE=450
export __GLX_VENDOR_LIBRARY_NAME=nvidia
export GBM_BACKEND=nvidia-drm

. "$HOME/.cargo/env"


# Added by Antigravity CLI installer
export PATH="__HOME__/.local/bin:$PATH"


export KILO_DISABLE_CLAUDE_CODE=1
export KILO_DISABLE_EXTERNAL_SKILLS=1
