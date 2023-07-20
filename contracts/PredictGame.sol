// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "@chainlink/contracts/src/v0.8/ChainlinkClient.sol";
import "@chainlink/contracts/src/v0.8/ConfirmedOwner.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
contract PredictGame is ChainlinkClient, ConfirmedOwner {
    using Chainlink for Chainlink.Request;

    //variables used for token and host

    ERC20 private ERC20interface;    
    address public tokenAdress; // This is the token address
    address payable public host; // This is the client
    event Transfer(address indexed _from, address indexed _to, uint256 _value);
    event Approval(address indexed _owner, address indexed _spender, uint256 _value);
    event APIurl(string api);

    //variables used for oracle
    address private oracle;
    bytes32 private jobId;
    uint256 private fee;
    
    event RequestVolume(bytes32 indexed requestId, uint256 volume);
    // mapping(uint256 => uint256) public ethUsdPrices; // Stores the ETH/USD price for each day

    //variables used for players
    enum BetDirection { Up, Down }
    struct Player{
        bool win;
        uint8 stage; // 스테이지는 0 ~ 6 까지 
        bool started;
        bool finished;
        uint256 betting_amount;
        uint256 startdate;
        uint temp; // temp 는 fulfill 함수에서 ethUsdPrices 를 차례대로 저장하기 위한 임시 증분값
        bool withdrawn;
    }
    mapping(uint256 => uint8) public datetemp; // 20230607 -> 0 (해당 날짜를 모두 ethUsdPrices 에 저장하면 6이 저장된다.)
    mapping(uint256 => uint256[4]) public ethUsdPrices; // 20230627 -> [1,2,3,4]
    mapping(address => Player) public players;

    constructor() ConfirmedOwner(msg.sender){
        // change to your token address
        tokenAdress = 0x7EA63fe16FDC8C7c6ac567C0e3cf3E0F859acc5D; 
        ERC20interface = ERC20(tokenAdress);
        host = payable(msg.sender);
        //default values
        setChainlinkToken(0x779877A7B0D9E8603169DdbD7836e478b4624789);
        setChainlinkOracle(0x6090149792dAAeE9D1D568c9f9a6F6B46AA29eFD);
        jobId = "ca98366cc7314957b8c012c72f05aeeb";
        fee = (1 * LINK_DIVISIBILITY) / 10; // 0,1 * 10**18 (Varies by network and job)

    }
    // *********** Oracle functions *************//


    //  this function changes uint256 to string uint256ToString(uint256 ) => returns string
   /*  used in uint256ToString(timestamps[i]) .... 
        req.add(
                "get",
                string(abi.encodePacked("https://min-api.cryptocompare.com/data/pricehistorical?fsym=ETH&tsyms=USD&ts=", uint256ToString(timestamps[i])))
                
            );  */

    function getTodaydate() public view returns(uint256){
        return getYearMonthDay(block.timestamp);
    }
    
    // this function sends API calls to Chainlink data feed ex) https://min-api.cryptocompare.com/data/pricehistorical?fsym=ETH&tsyms=USD&ts=1689080582
    function getDaysEthUsdPrices(uint256 _timestmap) public returns(bytes32 requestId) {
        Chainlink.Request memory req = buildChainlinkRequest(
            jobId,
            address(this),
            this.fulfill.selector
        );
        req.add(
            "get",
            string(abi.encodePacked("https://min-api.cryptocompare.com/data/pricemultifull?fsyms=ETH&tsyms=USD&ts=", Strings.toString(_timestmap)))
            
        );
        // Set the URL to perform the GET request on
        emit APIurl(string(abi.encodePacked("https://min-api.cryptocompare.com/data/pricemultifull?fsyms=ETH&tsyms=USD&ts=", Strings.toString(_timestmap))));

        // Set the path to find the desired data in the API response
        req.add("path", "RAW,ETH,USD,VOLUME24HOUR");

        // Multiply the result by 1000000000000000000 to remove decimals
        int256 timesAmount = 10 ** 18;
        req.addInt("times", timesAmount);

        // Sends the request
        return sendChainlinkRequest(req, fee);
    }
    // Helper function to get timestamps for the last 7 days
    function get4DaysTimestamps() public view returns (uint256[] memory) { // 거꾸로 저장되어있다.
        uint256[] memory timestamps = new uint256[](4);
        uint256 oneDay = 86400; // Number of seconds in a day

        for (uint256 i = 0; i < 4; i++) {
            timestamps[i] = block.timestamp - (i) * oneDay;
        }

        return timestamps;
    }

    function getYearMonthDay(uint256 timestamp) internal pure returns (uint256) {
        uint256 year = (timestamp / 31556926) + 1970; // 31556926 is the number of seconds in a year
        uint256 month = (timestamp / 2629743) % 12; // 2629743 is the number of seconds in a month
        uint256 day = (timestamp / 86400) % 31; // 86400 is the number of seconds in a day

        // Combine the components into a single uint256 value
        uint256 date = (year * 10000) + (month * 100) + day;

        return date;
    }

    function fulfill(bytes32 _requestId, uint256 _price) public recordChainlinkFulfillment(_requestId) {
        // Parse the requestId to get the day index (0-6) for the price
        emit RequestVolume(_requestId, _price);
        
        // mapping(address => uint256[7]) ethUsdPrices;
        if(datetemp[getYearMonthDay(block.timestamp)] == 0){
            ethUsdPrices[getYearMonthDay(block.timestamp)][datetemp[getYearMonthDay(block.timestamp)]++] = _price; 
        }
        else if(ethUsdPrices[getYearMonthDay(block.timestamp)][datetemp[getYearMonthDay(block.timestamp) - 1]] != _price){
            ethUsdPrices[getYearMonthDay(block.timestamp)][datetemp[getYearMonthDay(block.timestamp)]++] = _price; 
        }
        
    }

    // *************** token functions ****************** //
    
    function contractBalance() public view returns (uint _amount){
        return ERC20interface.balanceOf(address(this));
    }
    
    function senderBalance() public view returns (uint){
        return ERC20interface.balanceOf(msg.sender);
    }
    
    function approveSpendToken(uint _amount) public returns(bool){
        return ERC20interface.approve(address(this), _amount); // We give permission to this contract to spend the sender tokens
        //emit Approval(msg.sender, address(this), _amount);
    }
    
    function allowance() public view returns (uint){
        return ERC20interface.allowance(msg.sender, address(this));
    }
    
    
    function depositTokens (uint256 _amount) internal {
        address from = msg.sender;
        address to = address(this);

        ERC20interface.transferFrom(from, to, _amount);
    }
    

    function transferBack (address payable _to, uint256 amount) private {
        uint balance = ERC20interface.balanceOf(address(this)); // the balance of this smart contract
        require(balance >= amount,"The contract does not have enough tokens.");
        ERC20interface.transferFrom(address(this), _to, amount);
    }

    // ************ game functions *************** //
  /*   struct Player{
            bool win;
            uint8 stage;
            bool started;
            bool finished;
            uint256 betting_amount;
            uint256 startdate;
            uint256 temp;
            bool withdrawn;
        } */
    // 유저의 startdate 를 리턴한다.
    function getStartdate() public view returns(uint256){
        return players[msg.sender].startdate;
    } 
        // 유저의 현제 스테이지를 리턴한다.
    function  getStage() public view returns(uint8){
        return players[msg.sender].stage;
    }

    // 게임을 시작하는 함수,, 해당 함수를 불러오기 전에 ethUsdPrices 를 모두 불러온뒤 실행. Player 구조체를 초기화 한다.
    function startGame(uint256 _betting_amount) public{
        require(players[msg.sender].started != true, "the game has already started");
        require(datetemp[getYearMonthDay(block.timestamp)] == 4, "the Eth UsdPrices are not stored");
        depositTokens(_betting_amount);
        players[msg.sender] = Player(false,0,true,false, _betting_amount,0,0,false);
        players[msg.sender].startdate = getYearMonthDay(block.timestamp);
    }
    // 게임을 진행 시키는 함수
    function  predict(BetDirection betDirection) public returns(bool){ // (true : up , false : down) 게임이 종료되면 true 를 반환한다.
        require(players[msg.sender].started == true , "game hasn't started yet");
        require(players[msg.sender].finished == false, "the game is already over");
        if(players[msg.sender].stage == 3){ // 마지막 스테이지 일 경우 게임을 종료 시킨다. 
            players[msg.sender].finished = true;
            players[msg.sender].win = true;
            return true;
        } // 틀렸을때 게임을 종료 시킨다.
        else if(ethUsdPrices[players[msg.sender].startdate][players[msg.sender].stage] >= ethUsdPrices[players[msg.sender].startdate][players[msg.sender].stage+1] && (betDirection == BetDirection.Up)){ // down && up
            players[msg.sender].finished = true; // 최종 저장된 stage 는 해당 유저가 아직 깨지 못한 stage 이다.
            players[msg.sender].win = false;
            return true;
        }
        else if(ethUsdPrices[players[msg.sender].startdate][players[msg.sender].stage] <= ethUsdPrices[players[msg.sender].startdate][players[msg.sender].stage+1] && (betDirection == BetDirection.Down)){ // up && down
            players[msg.sender].finished = true; // 최종 저장된 stage 가 해당 유저의 최대 stage 이다.
            players[msg.sender].win = false;
            return true;
        }
        else{ // 배팅에서 이겼을때
            players[msg.sender].stage++;
            return false;
        }
    }

    // 게임을 종료 시키는 함수 전 스테이지에서 이겼을시 withdraw() 함수를 통해서 배팅 금액을 가져간다.
    function finishGame() public{
        require(players[msg.sender].finished == false, "the game is already over");
        require(players[msg.sender].started == true, "game hasn't started yet");
        players[msg.sender].finished = true;
        players[msg.sender].win = true;
    }


    // 게임이 끝났을시 인출 함수
    function withdraw() public {
        require(players[msg.sender].withdrawn == false, "You have already withdrawn.");
        require(players[msg.sender].finished == true, "the game is not over yet");
        require(players[msg.sender].win == true);
        transferBack(payable(msg.sender), players[msg.sender].betting_amount * (players[msg.sender].stage+1));
    }

    function withdrawLink() public onlyOwner {
        LinkTokenInterface link = LinkTokenInterface(chainlinkTokenAddress());
        require(
            link.transfer(msg.sender, link.balanceOf(address(this))),
            "Unable to transfer"
        );
    }
    
    function getethUsdPrices(uint256 _date) public view returns(uint256[4] memory ){
        return ethUsdPrices[_date];
    }

    
}