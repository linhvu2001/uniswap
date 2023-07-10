// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;


import './token.sol';
import "hardhat/console.sol";


contract TokenExchange is Ownable {
    string public exchange_name = 'uniswap';

    address tokenAddr = 0x5FbDB2315678afecb367f032d93F642f64180aa3;                                  // TODO: paste token contract address here
    Token public token = Token(tokenAddr);                                

    // Liquidity pool for the exchange
    uint private token_reserves = 0;
    uint private eth_reserves = 0;

    mapping(address => uint) private lps; 
    mapping(address => uint) private tokenAmount;
    // Needed for looping through the keys of the lps mapping
    address[] private lp_providers;                     

    // liquidity rewards
    uint private swap_fee_numerator = 3;                
    uint private swap_fee_denominator = 100;
    bool private lock = false;
    // Constant: x * y = k
    uint private k;

    constructor() {}

    //uint private denominationVal = 10**12;
    

    // Function createPool: Initializes a liquidity pool between your Token and ETH.
    // ETH will be sent to pool in this transaction as msg.value
    // amountTokens specifies the amount of tokens to transfer from the liquidity provider.
    // Sets up the initial exchange rate for the pool by setting amount of token and amount of ETH.
    function createPool(uint amountTokens)
        external
        payable
        onlyOwner
    {
        // This function is already implemented for you; no changes needed.

        // require pool does not yet exist:
        require (token_reserves == 0, "Token reserves was not 0");
        require (eth_reserves == 0, "ETH reserves was not 0.");

        // require nonzero values were sent
        require (msg.value > 0, "Need eth to create pool.");
        uint tokenSupply = token.balanceOf(msg.sender);
        require(amountTokens <= tokenSupply, "Not have enough tokens to create the pool");
        require (amountTokens > 0, "Need tokens to create pool.");
        tokenAmount[msg.sender] = amountTokens;
        token.transferFrom(msg.sender, address(this), amountTokens);
        token_reserves = token.balanceOf(address(this));
        eth_reserves = msg.value;
        k = token_reserves * eth_reserves;
    }

    // Function removeLP: removes a liquidity provider from the list.
    // This function also removes the gap left over from simply running "delete".
    function removeLP(uint index) private {
        require(index < lp_providers.length, "specified index is larger than the number of lps");
        lp_providers[index] = lp_providers[lp_providers.length - 1];
        tokenAmount[msg.sender] = 0;
        lp_providers.pop();
    }

    // Function getSwapFee: Returns the current swap fee ratio to the client.
    function getSwapFee() public view returns (uint, uint) {
        return (swap_fee_numerator, swap_fee_denominator);
    }

    // ============================================================
    //                    FUNCTIONS TO IMPLEMENT
    // ============================================================
    
    /* ========================= Liquidity Provider Functions =========================  */ 

    // Function addLiquidity: Adds liquidity given a supply of ETH (sent to the contract as msg.value).
    // You can change the inputs, or the scope of your function, as needed.
    function addLiquidity(uint max_exchange_rate, uint min_exchange_rate) 
        external 
        payable
    {
        /******* TODO: Implement this function *******/
        uint amountETH = msg.value;
        require(amountETH > 0, "Error: Supply of ETH not positive");

        uint tokensRequired = amountETH * token_reserves / eth_reserves;

        require(tokensRequired <= token.balanceOf(msg.sender), "Error: User does not have enough tokens");

        
        require(amountETH / tokensRequired >= min_exchange_rate, "Error: Below min exchange rate");
        require(amountETH / tokensRequired <= max_exchange_rate, "Error: Above max exchange rate");


        token.transferFrom(msg.sender, address(this), tokensRequired);
        token_reserves = token.balanceOf(address(this));

        eth_reserves = address(this).balance;

        k = token_reserves * eth_reserves;
        uint old_reserves = token_reserves - tokensRequired;
        bool senderExists = false;

        for (uint i=0; i<lp_providers.length; i++){
          if (lp_providers[i] == msg.sender){
            senderExists = true;
            lps[msg.sender] = (lps[msg.sender] * old_reserves + tokensRequired) / token_reserves;
          }else{
            lps[lp_providers[i]] *= old_reserves;
            lps[lp_providers[i]] /= token_reserves;
          }
        }

        if (!senderExists){
          lp_providers.push(msg.sender);
          lps[msg.sender] = tokensRequired / token_reserves;
        }

       
    }


    // Function removeLiquidity: Removes liquidity given the desired amount of ETH to remove.
    // You can change the inputs, or the scope of your function, as needed.
    function removeLiquidity(uint amountETH, uint max_exchange_rate, uint min_exchange_rate)
        public 
        payable
    {
        /******* TODO: Implement this function *******/
        
        require(!lock);
        lock = true;


        uint amountTokens = amountETH * token_reserves / eth_reserves;

        
        require(amountTokens <= (lps[msg.sender] * token_reserves), "Error: User does not have enough tokens");
        
        require(amountETH / amountTokens >= min_exchange_rate, "Error: Below min exchange rate");
        require(amountETH / amountTokens <= max_exchange_rate, "Error: Above max exchange rate");

        uint oldReserves = token_reserves;
        require(token_reserves - amountTokens > 0, "Error: Cannot deplete token reserves to 0");
        require(eth_reserves - amountETH > 0, "Error: Cannot deplete ETH reserves to 0");


        token.transfer(msg.sender, amountTokens);
        token_reserves = token.balanceOf(address(this));


        payable(msg.sender).transfer(amountETH);
        eth_reserves = address(this).balance;


        k = token_reserves * eth_reserves;


        lps[msg.sender] = ((lps[msg.sender] * oldReserves) - amountTokens) / token_reserves;

        uint senderIdx = 0;

        for (uint i=0; i<lp_providers.length; i++){
          if (lp_providers[i] == msg.sender){
            senderIdx = i;
          }else{
            lps[lp_providers[i]] *= oldReserves;
            lps[lp_providers[i]] /= token_reserves;
          }
        }

        if (lps[msg.sender] == 0){
          removeLP(senderIdx);
        }

        lock = false;
    }

    function removeAllLiquidity(uint max_exchange_rate, uint min_exchange_rate)
        external
        payable
    {
        /******* TODO: Implement this function *******/
        uint toRemove = lps[msg.sender] * token_reserves;
        if (token_reserves - toRemove < 1){
          toRemove -= 1;
        }
        uint amountETH = toRemove * eth_reserves / token_reserves;
        if (eth_reserves - amountETH < 1){
          amountETH -= 1;
        }
        removeLiquidity(amountETH, max_exchange_rate, min_exchange_rate);
    }
    /***  Define additional functions for liquidity fees here as needed ***/


    /* ========================= Swap Functions =========================  */ 

    // Function swapTokensForETH: Swaps your token with ETH
    // You can change the inputs, or the scope of your function, as needed.
    function swapTokensForETH(uint amountTokens, uint max_exchange_rate)
        external 
        payable
    {
        /******* TODO: Implement this function *******/

        require(!lock);
        lock = true;

        require(amountTokens > 0, "Error: Must swap a positive amount of Tokens");
        require(amountTokens <= token.balanceOf(msg.sender), "Error: Don\'t have enough tokens");

        uint amountETH = eth_reserves - (k / (token_reserves + amountTokens));
        uint fees = amountETH * swap_fee_numerator / swap_fee_denominator;
        amountETH -= fees;

        require(eth_reserves - amountETH >= 1, "Error: Cannot deplete ETH reserves below 1 ETH");

        require(eth_reserves / token_reserves <= max_exchange_rate, "Error: Exchange rate greater than specified rate");

        token.transferFrom(msg.sender, address(this), amountTokens);

        token_reserves = token.balanceOf(address(this));

        payable(msg.sender).transfer(amountETH);

        eth_reserves = address(this).balance;

        lock = false;
    }



    // Function swapETHForTokens: Swaps ETH for your tokens
    // ETH is sent to contract as msg.value
    // You can change the inputs, or the scope of your function, as needed.
    function swapETHForTokens(uint max_exchange_rate)
        external
        payable 
    {
        /******* TODO: Implement this function *******/



        require(!lock);
        lock = true;

        require(msg.value > 0, "Error: Must swap a positive amount of ETH");
        uint amountTokens = token_reserves - (k / (eth_reserves + msg.value));
        uint fees = amountTokens * swap_fee_numerator / swap_fee_denominator;
        amountTokens -= fees;
        require(token_reserves - amountTokens >= 1, "Error: Cannot deplete Token reserves below 1 Token");

        require(eth_reserves / token_reserves <= max_exchange_rate, "Error: Exchange rate greater than specified rate");

        eth_reserves = address(this).balance;

        token.transfer(msg.sender, amountTokens);

        token_reserves = token.balanceOf(address(this));
        lock = false;
    }


    function getTokenAmount() 
      external view returns (uint256){
        return lps[msg.sender];
    }


    function getTokenFromAccount() 
      external view returns (uint256){
        return token.balanceOf(msg.sender); 
    }
}
