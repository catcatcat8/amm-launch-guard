import 'module-alias/register'

import { HardhatUserConfig, task } from 'hardhat/config'
import 'hardhat-deploy'
import '@nomiclabs/hardhat-waffle'
import 'hardhat-gas-reporter'
import 'solidity-coverage'
import 'hardhat-contract-sizer'
import '@nomiclabs/hardhat-etherscan'
import '@typechain/hardhat'

import { useEvm } from '@/evm'

const {
  tools: { genCompilers, genNetworks },
} = useEvm()

task('accounts', 'Prints the list of accounts', async (_, hre) => {
  const accounts = await hre.ethers.getSigners()
  for (const account of accounts) console.log(account.address)
})

task('wallets', 'Create new wallet', async (_, hre) => {
  for (let i = 0; i < 5; i++) {
    const wallet = hre.ethers.Wallet.createRandom()
    console.log({
      address: wallet.address,
      privateKey: wallet.privateKey,
    })
  }
})

const config: HardhatUserConfig = {
  solidity: {
    compilers: genCompilers('0.8.18'),
  },
  networks: {
    hardhat: {
      tags: ['localhost'],
      deploy: ['deploy/localhost/'],

      forking: {
        url: 'https://rpc.ankr.com/bsc',
      },
    },
    ...genNetworks(),
    // place here any network you like (for overriding `genNetworks`)
  },
  gasReporter: {
    enabled: true,
    currency: 'USD',
  },
  contractSizer: {
    alphaSort: true,
    disambiguatePaths: false,
    runOnCompile: true,
  },
}

export default config
