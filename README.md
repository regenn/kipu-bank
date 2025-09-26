# KipuBank 

KipuBank es un Smart Contract escrito en Solidity que funciona como un banco descentralizado para ETH. Cada usuario puede depositar y retirar sus fondos de manera segura.


##  Despliegue
Se recomienda utilizar Remix IDE y utilizar una cuenta con ETH de prueba (Sepolia).


##  Interaccion con el contrato
Depositar ETH: 
  await kipuBank.connect(usuario).deposita({ valor: hre.ethers.parseEther("0.5") });
Retirar ETH:
  await kipuBank.connect(usuario).Retira(hre.ethers.parseEther("0.2"));
Consultar saldo y contadores:
  const saldo = await kipuBank.getSaldo(usuario.address);
  const totalAssets = await kipuBank.getTotalAssets();
  const depositos = await kipuBank.getContDeposito();
