function PLUGIN:Available(ctx)
  return require("catalog").list()
end
