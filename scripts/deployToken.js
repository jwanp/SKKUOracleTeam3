// global scope, and execute the script.
const {ethers} = require("hardhat");

async function main() {
  const  [deployer] = await ethers.getSigners();

  const Token = await ethers.deployContract("Token");
  await Token.waitForDeployment();

  console.log("Token deployed to:", Token.target);
  console.log("Deployer address:", deployer.address);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
