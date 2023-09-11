import { ethers } from 'hardhat'
import { expect } from 'chai'

import { BSC_BUSD, BSC_BUSD_HOLDER, useContracts } from '@/test'
import { deploy } from '@gotbit/evm-hardhat'
import { AntiSync__factory, Token, Token__factory } from '@/typechain'
import { ERRORS } from './utils/errors'
import { getTokens } from './utils/helpers'
import { BigNumber } from 'ethers/lib/ethers'
import { Pair__factory } from '@/typechain-pancake'

const ONE_TOKEN = BigNumber.from(10).pow(18)

describe('AntiSync contract', () => {
  beforeEach(async () => {
    await deploy()
  })
  it('Should execute constructor correctly', async () => {
    const { antiSync } = await useContracts()
    const [deployer] = await ethers.getSigners()

    expect(await antiSync.owner()).eq(deployer.address)
  })
  it('Constructor should revert', async () => {
    const [deployer] = await ethers.getSigners()

    const antiSync: AntiSync__factory = await ethers.getContractFactory(
      'AntiSync',
      deployer
    )

    await expect(antiSync.deploy(ethers.constants.AddressZero)).revertedWith(
      ERRORS.ZeroAddress
    )
  })
  it('Should anti-sync 1 token successfully', async () => {
    const { antiSync, token, router, factory } = await useContracts()
    const [deployer, scammer] = await ethers.getSigners()

    await factory.connect(deployer).createPair(token.address, BSC_BUSD)
    const pair = Pair__factory.connect(
      await factory.getPair(token.address, BSC_BUSD),
      ethers.provider
    )
    const BUSD = Token__factory.connect(BSC_BUSD, ethers.provider)

    const scammerBusdSync = 2
    await getTokens(
      BSC_BUSD,
      BSC_BUSD_HOLDER,
      BigNumber.from(scammerBusdSync),
      scammer.address
    )
    await BUSD.connect(scammer).transfer(pair.address, scammerBusdSync)
    await pair.connect(scammer).sync()

    const reserves = await pair.getReserves()
    expect(reserves._reserve0).eq(0)
    expect(reserves._reserve1).eq(scammerBusdSync)

    // 50/50 proportion
    await getTokens(
      BSC_BUSD,
      BSC_BUSD_HOLDER,
      ONE_TOKEN.mul(98),
      deployer.address
    )
    await token
      .connect(deployer)
      .approve(antiSync.address, ethers.constants.MaxUint256)
    await BUSD.connect(deployer).approve(
      antiSync.address,
      ethers.constants.MaxUint256
    )

    const balanceBeforeTokenA = await token.balanceOf(deployer.address)
    const balanceBeforeTokenB = await BUSD.balanceOf(deployer.address)

    await expect(
      router
        .connect(deployer)
        .addLiquidity(
          token.address,
          BUSD.address,
          100,
          98,
          0,
          0,
          deployer.address,
          '9999999999'
        )
    ).reverted

    const params = {
      router: router.address,
      tokenA: token.address,
      tokenB: BUSD.address,
      currentReservesA: 0,
      currentReservesB: 2,
      amountAToSync: 2,
      amountBToSync: 0,
      amountADesired: ONE_TOKEN.mul(98).sub(2),
      amountBDesired: ONE_TOKEN.mul(98).sub(2),
      amountAMin: ONE_TOKEN.mul(98).sub(2),
      amountBMin: ONE_TOKEN.mul(98).sub(2),
      to: deployer.address,
    }
    await antiSync.connect(deployer).syncAndAddLiquidity(params)

    expect(await token.balanceOf(deployer.address)).eq(
      balanceBeforeTokenA.sub(params.amountADesired.add(params.amountAToSync))
    )
    expect(await BUSD.balanceOf(deployer.address)).eq(
      balanceBeforeTokenB.sub(params.amountBDesired.add(params.amountBToSync))
    )

    expect(await token.balanceOf(antiSync.address)).eq(0)
    expect(await BUSD.balanceOf(antiSync.address)).eq(0)

    const reserves2 = await pair.getReserves()
    expect(reserves2._reserve0).eq(ONE_TOKEN.mul(98))
    expect(reserves2._reserve1).eq(ONE_TOKEN.mul(98))
  })
  it('Should anti-sync 2 tokens successfully', async () => {
    const { antiSync, token, router, factory } = await useContracts()
    const [deployer, scammer] = await ethers.getSigners()

    await factory.connect(deployer).createPair(token.address, BSC_BUSD)
    const pair = Pair__factory.connect(
      await factory.getPair(token.address, BSC_BUSD),
      ethers.provider
    )
    const BUSD = Token__factory.connect(BSC_BUSD, ethers.provider)

    const scammerBusdSync = 2
    await getTokens(
      BSC_BUSD,
      BSC_BUSD_HOLDER,
      BigNumber.from(scammerBusdSync),
      scammer.address
    )
    await BUSD.connect(scammer).transfer(pair.address, scammerBusdSync)
    await pair.connect(scammer).sync()

    // 2/3 proportion
    await getTokens(
      BSC_BUSD,
      BSC_BUSD_HOLDER,
      ONE_TOKEN.mul(100),
      deployer.address
    )
    await token
      .connect(deployer)
      .approve(antiSync.address, ethers.constants.MaxUint256)
    await BUSD.connect(deployer).approve(
      antiSync.address,
      ethers.constants.MaxUint256
    )

    const balanceBeforeTokenA = await token.balanceOf(deployer.address)
    const balanceBeforeTokenB = await BUSD.balanceOf(deployer.address)

    const params = {
      router: router.address,
      tokenA: BUSD.address,
      tokenB: token.address,
      currentReservesA: 2,
      currentReservesB: 0,
      amountAToSync: 1,
      amountBToSync: 2,
      amountADesired: ONE_TOKEN.mul(30),
      amountBDesired: ONE_TOKEN.mul(20),
      amountAMin: ONE_TOKEN.mul(30),
      amountBMin: ONE_TOKEN.mul(20),
      to: deployer.address,
    }
    await antiSync.connect(deployer).syncAndAddLiquidity(params)

    expect(await token.balanceOf(deployer.address)).eq(
      balanceBeforeTokenA.sub(params.amountBDesired.add(params.amountBToSync))
    )
    expect(await BUSD.balanceOf(deployer.address)).eq(
      balanceBeforeTokenB.sub(params.amountADesired.add(params.amountAToSync))
    )

    expect(await token.balanceOf(antiSync.address)).eq(0)
    expect(await BUSD.balanceOf(antiSync.address)).eq(0)

    const reserves2 = await pair.getReserves()
    expect(reserves2._reserve0).eq(ONE_TOKEN.mul(20).add(2))
    expect(reserves2._reserve1).eq(ONE_TOKEN.mul(30).add(3))
  })
  it('Anti-sync should be reverted', async () => {
    const { antiSync, token, router, factory } = await useContracts()
    const [deployer, scammer] = await ethers.getSigners()

    await factory.connect(deployer).createPair(token.address, BSC_BUSD)
    const pair = Pair__factory.connect(
      await factory.getPair(token.address, BSC_BUSD),
      ethers.provider
    )
    const BUSD = Token__factory.connect(BSC_BUSD, ethers.provider)

    const scammerBusdSync = 2
    await getTokens(
      BSC_BUSD,
      BSC_BUSD_HOLDER,
      BigNumber.from(scammerBusdSync),
      scammer.address
    )
    await BUSD.connect(scammer).transfer(pair.address, scammerBusdSync)
    await pair.connect(scammer).sync()

    // 50/50 proportion
    await getTokens(
      BSC_BUSD,
      BSC_BUSD_HOLDER,
      ONE_TOKEN.mul(98),
      deployer.address
    )
    await token
      .connect(deployer)
      .approve(antiSync.address, ethers.constants.MaxUint256)
    await BUSD.connect(deployer).approve(
      antiSync.address,
      ethers.constants.MaxUint256
    )

    await expect(
      antiSync.connect(deployer).syncAndAddLiquidity({
        router: router.address,
        tokenA: token.address,
        tokenB: BUSD.address,
        currentReservesA: 0,
        currentReservesB: 2,
        amountAToSync: 2,
        amountBToSync: 0,
        amountADesired: ONE_TOKEN.mul(98).sub(2),
        amountBDesired: ONE_TOKEN.mul(98).sub(2),
        amountAMin: ONE_TOKEN.mul(98).sub(2),
        amountBMin: ONE_TOKEN.mul(98).sub(2),
        to: ethers.constants.AddressZero,
      })
    ).revertedWith(ERRORS.ZeroAddress)

    await expect(
      antiSync.connect(deployer).syncAndAddLiquidity({
        router: router.address,
        tokenA: token.address,
        tokenB: deployer.address,
        currentReservesA: 0,
        currentReservesB: 2,
        amountAToSync: 2,
        amountBToSync: 0,
        amountADesired: ONE_TOKEN.mul(98).sub(2),
        amountBDesired: ONE_TOKEN.mul(98).sub(2),
        amountAMin: ONE_TOKEN.mul(98).sub(2),
        amountBMin: ONE_TOKEN.mul(98).sub(2),
        to: deployer.address,
      })
    ).revertedWith(ERRORS.PairNotCreated)

    await expect(
      antiSync.connect(deployer).syncAndAddLiquidity({
        router: router.address,
        tokenA: token.address,
        tokenB: BUSD.address,
        currentReservesA: 1,
        currentReservesB: 2,
        amountAToSync: 2,
        amountBToSync: 0,
        amountADesired: ONE_TOKEN.mul(98).sub(2),
        amountBDesired: ONE_TOKEN.mul(98).sub(2),
        amountAMin: ONE_TOKEN.mul(98).sub(2),
        amountBMin: ONE_TOKEN.mul(98).sub(2),
        to: deployer.address,
      })
    ).revertedWith(ERRORS.WrongReserves)

    await expect(
      antiSync.connect(deployer).syncAndAddLiquidity({
        router: router.address,
        tokenA: BUSD.address,
        tokenB: token.address,
        currentReservesA: 3,
        currentReservesB: 0,
        amountAToSync: 0,
        amountBToSync: 2,
        amountADesired: ONE_TOKEN.mul(98).sub(2),
        amountBDesired: ONE_TOKEN.mul(98).sub(2),
        amountAMin: ONE_TOKEN.mul(98).sub(2),
        amountBMin: ONE_TOKEN.mul(98).sub(2),
        to: deployer.address,
      })
    ).revertedWith(ERRORS.WrongReserves)
  })

  it('Should anti-sync successfully and transfer all left tokens to sender', async () => {
    const { antiSync, token, router, factory } = await useContracts()
    const [deployer, scammer] = await ethers.getSigners()

    await factory.connect(deployer).createPair(token.address, BSC_BUSD)
    const pair = Pair__factory.connect(
      await factory.getPair(token.address, BSC_BUSD),
      ethers.provider
    )
    const BUSD = Token__factory.connect(BSC_BUSD, ethers.provider)

    const scammerBusdSync = 2
    await getTokens(
      BSC_BUSD,
      BSC_BUSD_HOLDER,
      BigNumber.from(scammerBusdSync),
      scammer.address
    )
    await BUSD.connect(scammer).transfer(pair.address, scammerBusdSync)
    await pair.connect(scammer).sync()

    const reserves = await pair.getReserves()

    // 50/50 proportion
    await getTokens(
      BSC_BUSD,
      BSC_BUSD_HOLDER,
      ONE_TOKEN.mul(98).mul(2),
      deployer.address
    )
    await token
      .connect(deployer)
      .approve(antiSync.address, ethers.constants.MaxUint256)
    await BUSD.connect(deployer).approve(
      antiSync.address,
      ethers.constants.MaxUint256
    )

    await antiSync.connect(deployer).syncAndAddLiquidity({
      router: router.address,
      tokenA: BUSD.address,
      tokenB: token.address,
      currentReservesA: 2,
      currentReservesB: 0,
      amountAToSync: 0,
      amountBToSync: 2,
      amountADesired: ONE_TOKEN.mul(98).add(1),
      amountBDesired: ONE_TOKEN.mul(98),
      amountAMin: ONE_TOKEN.mul(98),
      amountBMin: ONE_TOKEN.mul(98),
      to: deployer.address,
    })

    expect(await token.balanceOf(antiSync.address)).eq(0)
    expect(await BUSD.balanceOf(antiSync.address)).eq(0)

    const reserves2 = await pair.getReserves()
    expect(reserves2._reserve0).eq(ONE_TOKEN.mul(98).add(2))
    expect(reserves2._reserve1).eq(ONE_TOKEN.mul(98).add(2))

    // No anti-sync
    await antiSync.connect(deployer).syncAndAddLiquidity({
      router: router.address,
      tokenA: BUSD.address,
      tokenB: token.address,
      currentReservesA: ONE_TOKEN.mul(98).add(2),
      currentReservesB: ONE_TOKEN.mul(98).add(2),
      amountAToSync: 0,
      amountBToSync: 0,
      amountADesired: ONE_TOKEN.mul(98),
      amountBDesired: ONE_TOKEN.mul(98).add(1),
      amountAMin: ONE_TOKEN.mul(98),
      amountBMin: ONE_TOKEN.mul(98),
      to: deployer.address,
    })

    expect(await token.balanceOf(antiSync.address)).eq(0)
    expect(await BUSD.balanceOf(antiSync.address)).eq(0)
  })
})
