### Summary Of Changes

This PR implements a new library function that calculates the optimal amount to swap in order to supply to AMM  in the exact proportionate.

Reference:
- [Optimal One-sided Supply to Uniswap](https://blog.alphafinance.io/onesideduniswap/)
- [@shenrene 's research](https://www.dropbox.com/transfer/AAAAADCQOQCEgIndGf8WPlqPagEkNXNBvZPFxaxQ0Md_IWEHkXOWQ7E)

### Technical Description

Calculates the optimal amount of assets to swap in order to supply to AMM in the exact proportionate.
In order to preserve the calculation precision as much as possible, fee must be provided as an integer value, and in where extension represents the value used to extend fee.
i.e. If the fee of an AMM is 0.003%, fee and extension can be 3 and 1000, or 300 and 1e5.
The bigger extended, the more precise result is out, but the more intensive computation is required.
The biggest computation here is sqrt at the end.
The bigger parameters get in, the more intensive computation is required.
It assumes one-side swap, so, swap direction may be reversed as B to A depending on the AMM pool's ratio and the  amount to swap.
It reverts depending on arithmetic Overflow/Underflow, and any violation to the requirements.

**Function Signature**
```
@param amountA - The amount of asset A to be supplied to AMM. It can be 0, but amountA and amountB cannot be 0 at the same time.
@param amountB - The amount of asset B to be supplied to AMM. It can be 0, but amountA and amountB cannot be 0 at the same time.
@param reserveA - The reserved amount of asset A in the AMM pool. It cannot be 0.
@param reserveB - The reserved amount of asset B in the AMM pool. It cannot be 0.
@param fee - The swap fee in the AMM pool, but it must be extended value to be an integer.
@param extension - The value used to extend the swap fee.

@return 
reversed - Indicates that the swap direction should be reversed as B to A.
swapAmount - The amount of asset A or B to swap.
```

### Gas Optimization

Every equation in the function is straightforward as they are all arithmetic operation, except `sqrt`
Besides it, we can optimize `exp(2)` into `mul`. (`exp` costs more than `10` gas, while `mul` costs fixed `5`.)
This initial implementation is using "babylonian sqrt" method. But it costs high gas (more than 20K).
In contrast, `ABDKMathQuad` costs extremely cheaper, reeeeeeally. 😮
We may need to import a part of the library, if it is inefficient to bring the whole library source.

**UPDATE:**
Now, it is using uniswap's "Babylonian sqrt" method.

**NOTE:**
In this implementation, we try to avoid `div` in order to preserve the precision, and to avoid Solidity fraction "wrapping".
i.e. In order to compare LP ratio and asset ratio, it doesn't try
```solidity
reserveA / reserveB > amountA / amountB
```
(it's buggy ^^, can be zero at times)
instead,
```solidity
reserveA * amountB > reserveB * amountA
```

### Overflow Potentiality
For now, we have two math equations:
One is from [alpha homora](https://blog.alphafinance.io/onesideduniswap/) - assume it EQ1
Another one is from @rene’s [math](https://www.dropbox.com/transfer/AAAAADCQOQCEgIndGf8WPlqPagEkNXNBvZPFxaxQ0Md_IWEHkXOWQ7E) - assume it EQ2

The two equations are correct/valid, and EQ1 is used widely.

The main difference is EQ1 completely assumes that one of amtA or amtB is zero. This assumption is the main key what EQ1 looks so simple.
In contrast, EQ2 assumes that amtA and amtB can be non-zero at the same time.
Because of the one simple difference, EQ2 consists of complex math components, and one of them can be big enough that can cause overflow.
Please see the screenshot attached.
<img width="1259" alt="Screen Shot 2021-08-24 at 4 02 15 PM" src="https://user-images.githubusercontent.com/78368735/130843114-d493a01d-5d8f-4d78-bf02-acb6c9ff2f59.png">

Also, we need to multiply at least 1e3 in order to make the fee integer, so, the overflow possibility got increased.
max unsigned integer 256 bit = 1e77 approximately, in the screenshot, quadratic component is 5e75, then it's overflow because we multiply 1e3 it.

### Solution
So, depending on the assumption of one-side swap - wether a token amount is zero or not
We can apply as following:
- a token amount is zero - use simple EQ1
- two token amounts can be non-zero at the same time, then:
    1. design a new math equation that can avoid overflow and floating number - 0.003
    2. modify current implementation not to overflow, but we will lose the precision in the range 0 ~ 1e3
    3. divide the swap/addLiquidity action into two steps
       a. add liquidity some amount as many as one token amount reaches to zero
       b. swap one-side by using EQ1
       c. add liquidity the remaining.

(2.c.iii - it is applied in the current master implementation)

### Deep dive into Overflow
In the EQ2, the biggest math component is `b^2` in `b^2 - 4ac`.
Unfortunately, it cannot be extended to `(b - sqrt(4ac)) * (b + sqrt(4ac))`, since `c` can be negative.
So, we must avoid `b^2` that can over `1e75` (considering `0.003`, it can over `1e81` in reality)

### `uint512`
If we simulate `uint512`, can we achieve `b^2` without overflow?
What does it cost to us?

In order to implement multiplication of 512bit numbers, roughly we need 4 `mul`s + 3 `add`s + 4 `push`.
I don't think it costs too much.
@suranap Let's think about it later.

### Test Notes

In order to validate the function is correct, it implements an javascript mock, and ensures that those results are equal.
The javascript mock has been implemented based on the "real math" (not fraction wrapping) based on the equations defined in the spreadsheet.
And it compares the result with one returned from library.
Every time, the test uses an enough big random numbers as their parameters.

`yarn hardhat test test/library.spec.ts`

You should see the result like:

```
  OndoLibrary
    getOptimalSwapAmount
      ✓ should revert on invalid parameters provided (49ms)
      ✓ should return correct value
      ✓ should return correct value
      ✓ should return correct value
      ✓ should return correct value
      ✓ should return correct value
      ✓ should return correct value
      ✓ should return correct value
      ✓ should return correct value
      ✓ should return correct value
      ✓ should return correct value


  11 passing (4s)
```

### Gas Report
`REPORT_GAS=true yarn hardhat test test/library.spec.ts`

- uniswap's "Babylonian" method used for `sqrt` 🏆

```
·--------------------------------------------|---------------------------|-------------|-----------------------------·
|            Solc version: 0.8.3             ·  Optimizer enabled: true  ·  Runs: 100  ·  Block limit: 12450000 gas  │
·············································|···························|·············|······························
|  Methods                                                                                                           │
····················|························|·············|·············|·············|···············|··············
|  Contract         ·  Method                ·  Min        ·  Max        ·  Avg        ·  # calls      ·  eur (avg)  │
····················|························|·············|·············|·············|···············|··············
|  OndoLibraryMock  ·  getOptimalSwapAmount  ·      25620  ·      25734  ·      25666  ·            9  ·          -  │
····················|························|·············|·············|·············|···············|··············
|  Deployments                               ·                                         ·  % of limit   ·             │
·············································|·············|·············|·············|···············|··············
|  OndoLibraryMock                           ·          -  ·          -  ·     309129  ·        2.5 %  ·          -  │
·--------------------------------------------|-------------|-------------|-------------|---------------|-------------·
```

- `ABDKMathQuad` used for `sqrt`

```
·--------------------------------------------|---------------------------|-------------|-----------------------------·
|            Solc version: 0.8.3             ·  Optimizer enabled: true  ·  Runs: 100  ·  Block limit: 12450000 gas  │
·············································|···························|·············|······························
|  Methods                                                                                                           │
····················|························|·············|·············|·············|···············|··············
|  Contract         ·  Method                ·  Min        ·  Max        ·  Avg        ·  # calls      ·  eur (avg)  │
····················|························|·············|·············|·············|···············|··············
|  OndoLibraryMock  ·  getOptimalSwapAmount  ·      25502  ·      25858  ·      25728  ·           10  ·          -  │
····················|························|·············|·············|·············|···············|··············
|  Deployments                               ·                                         ·  % of limit   ·             │
·············································|·············|·············|·············|···············|··············
|  OndoLibraryMock                           ·          -  ·          -  ·     442951  ·        3.6 %  ·          -  │
·--------------------------------------------|-------------|-------------|-------------|---------------|-------------·
```

- pure "babylonian" method used for `sqrt`

```
·--------------------------------------------|---------------------------|-------------|-----------------------------·
|            Solc version: 0.8.3             ·  Optimizer enabled: true  ·  Runs: 100  ·  Block limit: 12450000 gas  │
·············································|···························|·············|······························
|  Methods                                                                                                           │
····················|························|·············|·············|·············|···············|··············
|  Contract         ·  Method                ·  Min        ·  Max        ·  Avg        ·  # calls      ·  eur (avg)  │
····················|························|·············|·············|·············|···············|··············
|  OndoLibraryMock  ·  getOptimalSwapAmount  ·      39404  ·      47362  ·      43499  ·            9  ·          -  │
····················|························|·············|·············|·············|···············|··············
|  Deployments                               ·                                         ·  % of limit   ·             │
·············································|·············|·············|·············|···············|··············
|  OndoLibraryMock                           ·          -  ·          -  ·     251606  ·          2 %  ·          -  │
·--------------------------------------------|-------------|-------------|-------------|---------------|-------------·
```

### Deployment Notes
- [x] New Dependencies
- [ ] New Migrations

Closes #423 
