function PLUGIN:PreInstall(ctx)
  return require("resolver").pre_install(ctx)
end
