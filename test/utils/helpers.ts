import { Token__factory } from '@/typechain'
import { BigNumber } from 'ethers/lib/ethers'
import { ethers } from 'hardhat'

export async function getTokens(
  token: string,
  fromHolder: string,
  amount: BigNumber,
  recipient: string
) {
  await ethers.provider.send('hardhat_impersonateAccount', [fromHolder])
  const fromHolderSigner = await ethers.getSigner(fromHolder)
  const tokenContract = Token__factory.connect(token, fromHolderSigner)
  await tokenContract.transfer(recipient, amount)
}
