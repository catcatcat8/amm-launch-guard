import { Chain, defineEvm, mocks, universalRpc } from '@gotbit/evm'
import { hardhatAdapter } from '@gotbit/evm-hardhat/lib/adapter'

import * as dotenv from 'dotenv'
dotenv.config()

const parsePrivates = (str: string | undefined) => {
  if (!str) return []
  return str.split(',').map((s) => s.trim())
}

export const useEvm = defineEvm({
  modules: {
    ...Chain(universalRpc()),
  },
  adapter: hardhatAdapter({
    PRIVATE: {
      TEST: parsePrivates(process.env.PRIVATE_TEST),
      MAIN: parsePrivates(process.env.PRIVATE_MAIN),
    },
    API: {
      ETH: process.env.API_ETH,
      BSC: process.env.API_BSC,
      POLYGON: process.env.API_POLYGON,
      AVAX: process.env.API_AVAX,
      FTM: process.env.API_FTM,
      ARBITRUM: process.env.API_ARBITRUM,
      CELO: process.env.API_CELO,
      METIS: process.env.API_METIS,
      CUBE: process.env.API_CUBE,
      OKEX: process.env.API_OKEX,
      CMP: process.env.API_CMP,
    },
  }),
})

export {}
