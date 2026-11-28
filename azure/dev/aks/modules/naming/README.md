# naming (Azure)

Pure naming for the Azure AKS composition: `<prefix><region><team><environment><NN>`
(e.g. `akseusd005dev01`, `rgeusd005dev01`, `steusd005dev01`) from `naming/azure.json`.
It creates nothing and authorizes nothing. Subnet names derive from `names.vnet`
(`<vnet>-system-01`, `<vnet>-user-01`). Node pool names are `<team><role><NN>`
(`d005sys01`, `d005usr01`, rotation `d005tmp01`): AKS Linux pools allow only 1-12 lowercase
letters and digits, and the nodes inherit them (`aks-d005sys01-<hash>-vmss000000`).
