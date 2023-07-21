require("@nomicfoundation/hardhat-toolbox");
require('@openzeppelin/hardhat-upgrades');
require('dotenv').config()
/** @type import('hardhat/config').HardhatUserConfig */
const { ALCHEMY_SAPI_KEY, SEPOLIA_PRIVATE_KEY } = process.env;
module.exports = {
  solidity: "0.8.18",

  networks: {
    sepolia: {
      url: ALCHEMY_SAPI_KEY,
      accounts: [`0x${SEPOLIA_PRIVATE_KEY}`]
    }
  }
};
