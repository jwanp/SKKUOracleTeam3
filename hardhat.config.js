require("@nomicfoundation/hardhat-toolbox");
require('@openzeppelin/hardhat-upgrades');

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: "0.8.18",

  networks: {
    sepolia : {
      url: alchemy api key
      accounts: [ private key ]
    }
  }
};
