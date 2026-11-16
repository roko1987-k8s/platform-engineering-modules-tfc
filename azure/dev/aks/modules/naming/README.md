# naming (Azure)

Pure naming for the Azure AKS composition: `<prefix><region><team><environment><NN>`
(e.g. `akseusd005dev01`, `rgeusd005dev01`, `steusd005dev01`) from `naming/azure.json`.
It creates nothing and authorizes nothing. Subnet names derive from `names.vnet`
(`<vnet>-system-01`, `<vnet>-user-01`).
