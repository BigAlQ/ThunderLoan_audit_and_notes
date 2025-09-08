~350 nSLOC/Complexity

# Terms

Liquidity Provider: Someone who deposits money into a protocol to earn interest.

- Where is the money coming from?
  - TSwap: fees from swapping
  - Thunder Loans?: Fee from loans?

Thunderloan:

Token -> Deposit -> assetToken?

# notes

## AssetToken.sol

onlyThunderLoan is a modifer that only allows the thunderloan address to call it. This address is initilized at deployment.

the function updateExchangeRate's equation:
newExchangeRate = (totalAssets + fee) / totalSupply

How to derive:
exchangeRate = totalUnderlying / totalSupply

When you add a fee, you are adding the total Underlying value by the fee amount.

So:

newTotalUnderlying = oldTotalUnderlying + fee

exchangeRate = (oldTotalUnderlying + fee) / totalSupply

If you split the numerator you get:

exchangeRate = (oldTotalUnderlying / totalSupply) + (fee / totalSupply)

But wait, the oldExchangeRate equals oldTotalUnderlying / totalSupply

Plug in:

exchangeRate = (oldTotalUnderlying / totalSupply) + (fee / totalSupply)

exchangeRate = (oldExchangeRate) + (fee / totalSupply)

Done.

# Questions

Q: Why are we using TSwap? What does that have to do with flash loans?
