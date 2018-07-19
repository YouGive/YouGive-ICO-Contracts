pragma solidity ^0.4.21;
/**
 * @title SafeMath
 * @dev Math operations with safety checks that throw on error
 */
contract SafeMath {

  function safeSub(uint256 x, uint256 y) internal pure returns (uint256) {
    uint256 z = x - y;
    assert(z <= x);
    return z;
  }

  function safeAdd(uint256 x, uint256 y) internal pure returns (uint256) {
    uint256 z = x + y;
    assert(z >= x);
    return z;
  }
	
  function safeDiv(uint256 x, uint256 y) internal pure returns (uint256) {
    uint256 z = x / y;
    return z;
  }
	
  function safeMul(uint256 x, uint256 y) internal pure returns (uint256) {
    uint256 z = x * y;
    assert(x == 0 || z / x == y);
    return z;
  }

  function min(uint256 x, uint256 y) internal pure returns (uint256) {
    uint256 z = x <= y ? x : y;
    return z;
  }

  function max(uint256 x, uint256 y) internal pure returns (uint256) {
    uint256 z = x >= y ? x : y;
    return z;
  }
}


/**
 * @title Ownable contract - base contract with an owner
 */
contract Ownable {
  
  address public owner;
  address public newOwner;

  event OwnershipTransferred(address indexed _from, address indexed _to);
  
  /**
   * @dev The Ownable constructor sets the original `owner` of the contract to the sender account.
   */
  function Ownable () public {
    owner = msg.sender;
  }

  /**
   * @dev Throws if called by any account other than the owner.
   */
  modifier onlyOwner() {
    assert(msg.sender == owner);
    _;
  }

  /**
   * @dev Allows the current owner to transfer control of the contract to a newOwner.
   * @param _newOwner The address to transfer ownership to.
   */
  function transferOwnership(address _newOwner) public onlyOwner {
    assert(_newOwner != address(0));      
    newOwner = _newOwner;
  }

  /**
   * @dev Accept transferOwnership.
   */
  function acceptOwnership() public {
    if (msg.sender == newOwner) {
      emit OwnershipTransferred(owner, newOwner);
      owner = newOwner;
    }
  }
}

/**
 * @title ERC223 interface
 * @dev see https://github.com/ethereum/EIPs/issues/223
 */
contract ERC223 {
  uint public totalSupply;
  function balanceOf(address who) public view returns (uint);
  
  function name() public view returns (string _name);
  function symbol() public view returns (string _symbol);
  function decimals() public view returns (uint _decimals);
  function totalSupply() public view returns (uint256 _supply);

  function transfer(address to, uint value) public returns (bool ok);
  function transfer(address to, uint value, bytes data) public returns (bool ok);
  function transfer(address to, uint value, bytes data, string custom_fallback) public returns (bool ok);
  
  event Transfer(address indexed from, address indexed to, uint value, bytes indexed data);
}


/**
 * @title exchangeRate interface
 * @dev 
 */
contract exchangeRateContract {
  uint public exchangeRate;
}

/**
 * @title YouGive
 * @dev 
 */
contract YouGive is Ownable, SafeMath {

  /* The token we are selling */
  ERC223 public token;
  
  /* the UNIX timestamp start date of the crowdsale */
  uint public startsAt;
  
  /* the UNIX timestamp end date of the crowdsale */
  uint public endsAt;  
  
  /* 5% of tokens will be transfered to this address for marketing */
  address public marketingAddress;
  
  /* 18% of tokens will be transfered to this address for reservation */
  address public reserveAddress;
  
  /* 12% of tokens will be transfered to this address on the team */
  address public teamAddress;
  
  /* Eth will be transfered from this address */
  address public multisigWallet;
  
  /* Has this crowdsale been finalized */
  bool public finalized;
  
  /* The number of tokens already sold through this contract*/
  uint public tokensSold = 0;
  
  /* How much ETH each address has invested to this crowdsale */
  mapping (address => uint256) public investedAmountOf;
  
  /* How much tokens this crowdsale has credited for each investor address */
  mapping (address => uint256) public tokenAmountOf;
  
  /* How many wei of funding we have raised */
  uint public weiRaised = 0;
  
  /* How many unique addresses that have invested */
  uint public investorCount = 0;
  
  /* Service variables */
  uint public countUse;
  exchangeRateContract public rate;
  
  uint SoftCap;
  uint HardCap;
  
  struct Stage {
    // UNIX timestamp when the stage begins
    uint start;
    // UNIX timestamp when the stage is over
    uint end;
    // Token price in USD cents
    uint price;
    // Cap preceding the periods
    uint cap;
    // Token sold in period
    uint tokenSold;
  }
  Stage[] public stages;
  uint public periodStage;
  uint public currentPeriod;
  /* The address that can change the exchange rate */
  address public cryptoAgent;
  
  /** State machine
   *
   * - Preparing: All contract initialization calls and variables have not been set yet
   * - PreFunding: Private sale
   * - Funding: Active crowdsale
   * - Success: Softcap reached
   * - Failure: Softcap not reached before ending time
   * - Finalized: The finalized has been called and succesfully executed
   */
  enum State{Unknown, Preparing, PreFunding, Funding, Success, Failure, Finalized}
  
  /* A new investment was made */
  event Invested(address investor, uint weiAmount, uint tokenAmount);
   
  /**
   * @dev The function can be called only by cryptoAgent.
   */
  modifier onlyCryptoAgent() {
    assert(msg.sender == cryptoAgent);
    _;
  }
  
  /**
   * @dev Construct the token.
   * @param _marketingAddress 5% of tokens will be transfered to this address for marketing
   * @param _reserveAddress 18% of tokens will be transfered to this address for reservation
   * @param _teamAddress 12% of tokens will be transfered to this address on the team
   * @param _exchangeRateAddress  address of the ETH exchange rate contract on USD
   * @param _multisigWallet team wallet
   */
  function YouGive(address _marketingAddress, address _reserveAddress, address _teamAddress, address _exchangeRateAddress, address _multisigWallet) public {
    marketingAddress = _marketingAddress;
    reserveAddress = _reserveAddress;
    teamAddress = _teamAddress;
    rate = exchangeRateContract(_exchangeRateAddress);
    multisigWallet = _multisigWallet;
  }
   
  /**
   * Buy tokens from the contract
   */
  function() public payable {
    investInternal(msg.sender);
  }
  
  /**
   * Make an investment.
   *
   * Crowdsale must be running for one to invest.
   * We must have not pressed the emergency brake.
   *
   * @param receiver The Ethereum address who receives the tokens
   *
   */
  function investInternal(address receiver) private {

    require(msg.value > 0);
    require(getState() == State.Funding || getState() == State.PreFunding);

    uint weiAmount = msg.value;
    
    // Determine in what period we hit
    currentPeriod = getStage();
    
    // Calculating the number of tokens
    uint tokenAmount = calculateTokens(weiAmount,currentPeriod);
    
    require(tokenAmount > 0);
    
    if(currentPeriod == 0){
      require(tokenAmount >= 100*10**token.decimals());
    }
    
    // Check that we did not bust the cap in the period
    require(stages[currentPeriod].cap >= safeAdd(tokenAmount, stages[currentPeriod].tokenSold));
    
    stages[currentPeriod].tokenSold = safeAdd(stages[currentPeriod].tokenSold,tokenAmount);
	
    uint _tokenHolder = token.balanceOf(this);
    require(safeAdd(safeSub(token.totalSupply(),_tokenHolder),tokenAmount) <= stages[currentPeriod].cap);
    
    if (stages[currentPeriod].cap == safeAdd(safeSub(token.totalSupply(),_tokenHolder),tokenAmount)){
      updateStage(currentPeriod);
      endsAt = stages[stages.length-1].end;
    }
    /*
    if (stages[currentPeriod].cap == stages[currentPeriod].tokenSold){
      updateStage(currentPeriod);
      endsAt = stages[stages.length-1].end;
    }
    */
    if(investedAmountOf[receiver] == 0) {
       // A new investor
       investorCount++;
    }

    // Update investor
    investedAmountOf[receiver] = safeAdd(investedAmountOf[receiver],weiAmount);
    tokenAmountOf[receiver] = safeAdd(tokenAmountOf[receiver],tokenAmount);

    // Update totals
    weiRaised = safeAdd(weiRaised,weiAmount);
    tokensSold = safeAdd(tokensSold,tokenAmount);

    //send ether to the fund collection wallet
    multisigWallet.transfer(weiAmount);
    
    assignTokens(receiver, tokenAmount);

    // Tell us invest was success
    emit Invested(receiver, weiAmount, tokenAmount);
	}
 
  /**
   * Make an investment.
   *
   * Crowdsale must be running for one to invest.
   * We must have not pressed the emergency brake.
   *
   * @param receiver The Ethereum address who receives the tokens
   * @param _tokenAmount tokens
   *
   */
  function investCryptoAgent(address receiver, uint _tokenAmount) public onlyCryptoAgent {

    require(getState() == State.Funding || getState() == State.PreFunding);

    // Determine in what period we hit
    currentPeriod = getStage();
    
    // Calculating the number of tokens
    uint tokenAmount = _tokenAmount;
    
    require(tokenAmount > 0);
    
    if(currentPeriod == 0){
      require(tokenAmount >= 100*10**token.decimals());
    }
    
    // Check that we did not bust the cap in the period
    require(stages[currentPeriod].cap >= safeAdd(tokenAmount, stages[currentPeriod].tokenSold));
    
    stages[currentPeriod].tokenSold = safeAdd(stages[currentPeriod].tokenSold,tokenAmount);
	
    uint _tokenHolder = token.balanceOf(this);
    require(safeAdd(safeSub(token.totalSupply(),_tokenHolder),tokenAmount) <= stages[currentPeriod].cap);
    
    if (stages[currentPeriod].cap == safeAdd(safeSub(token.totalSupply(),_tokenHolder),tokenAmount)){
      updateStage(currentPeriod);
      endsAt = stages[stages.length-1].end;
    }
    /*
    if (stages[currentPeriod].cap == stages[currentPeriod].tokenSold){
      updateStage(currentPeriod);
      endsAt = stages[stages.length-1].end;
    }
    */
    if(tokenAmountOf[receiver] == 0) {
       // A new investor
       investorCount++;
    }

    // Update investor
    tokenAmountOf[receiver] = safeAdd(tokenAmountOf[receiver],tokenAmount);

    // Update totals
    tokensSold = safeAdd(tokensSold,tokenAmount);
    
    assignTokens(receiver, tokenAmount);

    // Tell us invest was success
    emit Invested(receiver, 0, tokenAmount);
	}
  
  /**
   * @dev 
   * @param _token address crowd sale
   */
  function setTokenAddress(address _token) public onlyOwner {
    token = ERC223(_token);
  }
  
  /**
   * @dev 
   * @param _startsAt start time ICO
   */
  function initContract(uint _startsAt) public onlyOwner {
    require(address(token) != address(0));
    SoftCap = 7700000*10**token.decimals();
    HardCap = 28600000*10**token.decimals();
    startsAt = _startsAt;
    stages.push(Stage(startsAt, startsAt+61 days, 60, 2000000*10**token.decimals(), 0));
    stages.push(Stage(startsAt+93 days, startsAt+105 days, 70, 7700000*10**token.decimals(), 0));
    stages.push(Stage(startsAt+105 days, startsAt+119 days, 75, 13700000*10**token.decimals(), 0));
    stages.push(Stage(startsAt+119 days, startsAt+133 days, 80, 19300000*10**token.decimals(),0));
    stages.push(Stage(startsAt+133 days, startsAt+147 days, 85, 25300000*10**token.decimals(), 0));
    stages.push(Stage(startsAt+147 days, startsAt+165 days, 90, 28600000*10**token.decimals(), 0));
    endsAt = startsAt+164 days;
  }
  
  /**
   * @dev Transfer of tokens for project development after completion of ICO
   */
  function takeDevelopmentTokens() public onlyOwner {
    require(endsAt < block.timestamp);
    require(!finalized);
    assignTokens(marketingAddress,2200000*10**token.decimals());
    assignTokens(reserveAddress,7920000*10**token.decimals());
    if(HardCap > tokensSold){
      assignTokens(address(0),safeSub(HardCap,tokensSold));
    }
    finalized = true;
  }
  
  /**
   * @dev Transfer of tokens to project developers according to the conditions
   */
  function takeTeamTokens() public onlyOwner {
    require(finalized);
    uint timePassed = block.timestamp - endsAt;
    uint countNow = safeDiv(timePassed,180 days);
    if(countNow > 3) {
      countNow = 3;
    }
    uint difference = safeSub(countNow,countUse);
    assert(difference>0);
    assignTokens(teamAddress,safeMul(difference,1760000*10**token.decimals()));
    countUse = safeAdd(countUse,difference);
  }
  
  /**
   * @dev 
   * @param _marketingAddress 5% of tokens will be transfered to this address for marketing
   * @param _reserveAddress 18% of tokens will be transfered to this address for reservation
   * @param _teamAddress 12% of tokens will be transfered to this address on the team
   * @param _multisigWallet team wallet
   */
  function changeAddress(address _marketingAddress, address _reserveAddress, address _teamAddress, address _multisigWallet) public onlyOwner {
    marketingAddress = _marketingAddress;
    reserveAddress = _reserveAddress;
    teamAddress = _teamAddress;
    multisigWallet = _multisigWallet;
  }
  
  /**
   * @dev 
   * @param _exchangeRateAddress current rate contract
   */
  function setExchangeRateAddress(address _exchangeRateAddress) public onlyOwner {
    rate = exchangeRateContract(_exchangeRateAddress);
  }
  
  /**
   * @dev Transfer issued tokens to the investor depending on the cap model.
   * @param _to dest address
   * @param _value tokens amount
   */
  function assignTokens(address _to, uint256 _value) private {
     token.transfer(_to, _value);
  }
  
  /**
   * @dev Check if Softcap was reached.
   * @return true if the crowdsale has raised enough money to be a success
   */
  function isCrowdsaleFull() public constant returns (bool) {
    if(tokensSold >= SoftCap){
      return true;  
    }
    return false;
  }
  
  /**
   * @dev Set the addres that can call setExchangeRate function.
   * @param _cryptoAgent crowdsale contract address
   */
  function setCryptoAgent(address _cryptoAgent) public onlyOwner {
    cryptoAgent = _cryptoAgent;
  }
  
  /** 
   * @dev Crowdfund state machine management.
   * @return State current state
   */
  function getState() public constant returns (State) {
    if (finalized) return State.Finalized;
    else if (address(token) == 0 || address(marketingAddress) == 0 || address(reserveAddress) == 0 || address(teamAddress) == 0 || address(rate) == 0 || block.timestamp < startsAt) return State.Preparing;
    else if (block.timestamp >= stages[0].start && block.timestamp <= stages[0].end) return State.PreFunding;
    else if (block.timestamp >= stages[1].start && block.timestamp <= stages[5].end) return State.Funding;
    else if (block.timestamp < stages[1].start) return State.Preparing;
    else if (isCrowdsaleFull()) return State.Success;
    else return State.Failure;
  }
  
  /**
   * @dev Converts wei value into USD cents according to current exchange rate
   * @param weiValue wei value to convert
   * @return USD cents equivalent of the wei value
   */
  function weiToUsdCents(uint weiValue) internal constant returns (uint) {
    return safeDiv(safeMul(weiValue, rate.exchangeRate()), 1e18);
  }
  
  /**
   * @dev Calculating tokens count
   * @param weiAmount invested
   * @param period period
   * @return tokens amount
   */
  function calculateTokens(uint weiAmount,uint period) internal constant returns (uint) {
    uint usdAmount = weiToUsdCents(weiAmount);
    uint multiplier = 10 ** token.decimals();
    uint price = stages[period].price;
    if(period == 0 && usdAmount >= 1000000){
      price = 50;
    }
    return safeDiv(safeMul(multiplier, usdAmount),price);
  }
  
  /** 
   * @dev Updates the ICO steps if the cap is reached.
   */
  function updateStage(uint number) private {
    require(number>=0);
    uint _time = block.timestamp;
    uint i;
      if(number == 0){
        stages[0].end = _time;
        stages[1].start = stages[0].end + 32 days;
        stages[1].end =  stages[1].start + 12 days;
        for (i = number+2; i < stages.length-1; i++) {
          stages[i].start = stages[i-1].end;
          stages[i].end = stages[i].start + 14 days;
        }
        stages[5].start = stages[4].end;
        stages[5].end =  stages[5].start + 18 days;
      }else if((number >= 1) && (number<=4)){
        stages[number].end =  _time;
        for (i = number+1; i < stages.length-1; i++) {
          stages[i].start = stages[i-1].end;
          stages[i].end = stages[i].start + 14 days;
        }
        stages[5].start = stages[4].end;
        stages[5].end =  stages[5].start + 18 days;
      }else if(number == 5){
        stages[5].end =  _time;
      }
  }
  
  /** 
   * @dev Gets the current stage.
   * @return uint current stage
   */
  function getStage() public constant returns (uint){
    for (uint i = 0; i < stages.length; i++) {
      if (block.timestamp >= stages[i].start && block.timestamp < stages[i].end) {
        return i;
      }
    }
    return stages.length-1;
  }
}
