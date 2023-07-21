// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "@chainlink/contracts/src/v0.8/ChainlinkClient.sol";
import "@chainlink/contracts/src/v0.8/ConfirmedOwner.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
contract PredictGame is ChainlinkClient, ConfirmedOwner {
    using Chainlink for Chainlink.Request;

    //variables used for token and host

    ERC20 private ERC20interface;    // ERC20 토큰을 다루기 위한 인터페이스
    address public tokenAdress; // This is the token address
    address payable public host; // This is the client
    event Transfer(address indexed _from, address indexed _to, uint256 _value); // 토큰을 보냈을때 로그
    event Approval(address indexed _owner, address indexed _spender, uint256 _value); // 
    event APIurl(string api); // getDaysEthUsdPrices 를 실행할때 request 를 보내는 url 의 로그를 찍는 이벤트

    //variables used for oracle
    address private oracle; // 오라클 주소
    bytes32 private jobId; // jobid
    uint256 private fee; // link fee
    
    event RequestVolume(bytes32 indexed requestId, uint256 volume);

    //variables used for players
    enum BetDirection { Up, Down } // ETH 가 올라갈지 내려갈예측 할때 파라미터로 쓰인다. predict(up_down) 에서 up_down 의 타입이다.
    struct Player{  // 플레이어의 현제 상태들을 나타내는 변수들로 구성된 구조체
        bool win; // 게임이 종료되고 이겼으면 true, 디폴트 값은 false
        uint8 stage; // 스테이지는 0 ~ 4 까지. predict() 랑 withdraw() 함수에서 쓰인다.
        bool started; // 플레이어가 startGame() 함수를 실행시 true 로 변경.  
        bool finished; // predict() 혹은 finishGame() 에서 쓰인다. 게임이 종료 되었을때 true 로 변경
        uint256 betting_amount; // startGame() 에서 얼마나 배팅했는지를 저장.
        uint256 startdate; // 플레이어가 게임을 시작한 날짜를 저장. ex) 20230627. | ethUsdPrices[20230627][0] 을 조회할때 쓰인다.
        bool withdrawn; // 예측 성공후 게임 종료시 token 을 인출했는지 알려주는 변수. 디폴트 값은 false. 인출후 true
    }
    mapping(uint256 => uint8) public datetemp; // 20230607 -> 0 (해당 날짜를 모두 ethUsdPrices 에 저장하면 6이 저장된다.)
    mapping(uint256 => uint256[4]) public ethUsdPrices; // 20230627 -> [가격1, 가격2, 가격3, 가격4]. (시작날자 -> 가격 4개 매핑)
    mapping(address => Player) public players; // address -> player 구조체 

    constructor() ConfirmedOwner(msg.sender){
        // change to your token address
        tokenAdress = 0x7EA63fe16FDC8C7c6ac567C0e3cf3E0F859acc5D; // 배포된 tokenAddress 를 입력
        ERC20interface = ERC20(tokenAdress); // ERC20 인터페이스로 해당 token address 를 감싼다.
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

    // 현재날짜를 가져오는 함수 ex) 20230612 값을 반환한다.
    function getTodaydate() public view returns(uint256){
        return getYearMonthDay(block.timestamp);
    }
    
    // this function sends API calls to Chainlink data feed ex) https://min-api.cryptocompare.com/data/pricehistorical?fsym=ETH&tsyms=USD&ts=1689080582

    // 오라클 HTTP request 를 보내는 함수
    // _timestamp 를 파라미터로 받은뒤 마지막에 concat 한 url 로 request 로 보낸다.
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
        // requst를 보낸 URL 을 확인하는 로그를 찍는다.
        emit APIurl(string(abi.encodePacked("https://min-api.cryptocompare.com/data/pricemultifull?fsyms=ETH&tsyms=USD&ts=", Strings.toString(_timestmap))));

        // Set the path to find the desired data in the API response
        req.add("path", "RAW,ETH,USD,VOLUME24HOUR");

        // Multiply the result by 1000000000000000000 to remove decimals
        int256 timesAmount = 10 ** 18;
        req.addInt("times", timesAmount);

        // Sends the request
        return sendChainlinkRequest(req, fee);
    }
    // 4일 간격의 block.timestamp 를 리턴한다. 해당 리턴값은 getDaysEthU은dPrices 의 파라미터로 쓰인다.
    function get4DaysTimestamps() public view returns (uint256[] memory) { // 거꾸로 저장되어있다.
        uint256[] memory timestamps = new uint256[](4);
        uint256 oneDay = 86400; // Number of seconds in a day

        for (uint256 i = 0; i < 4; i++) {
            timestamps[i] = block.timestamp - (i) * oneDay;
        }

        return timestamps;
    }
    // timestamp 를 날짜로 바꿔준다. 예 1689909960 -> 20230624
    function getYearMonthDay(uint256 timestamp) internal pure returns (uint256) {
        uint256 year = (timestamp / 31556926) + 1970; // 31556926 is the number of seconds in a year
        uint256 month = (timestamp / 2629743) % 12; // 2629743 is the number of seconds in a month
        uint256 day = (timestamp / 86400) % 31; // 86400 is the number of seconds in a day

        // Combine the components into a single uint256 value
        uint256 date = (year * 10000) + (month * 100) + day;

        return date;
    }
    // getDaysEthU은dPrices() 의 response 를 받은것을 처리하는 함수;;
    function fulfill(bytes32 _requestId, uint256 _price) public recordChainlinkFulfillment(_requestId) {
        // Parse the requestId to get the day index (0-6) for the price
        emit RequestVolume(_requestId, _price);
        
        // datetemp[startdate] 으로 startdate 해당하는 가격을 어디까지 불러왔는지 알 수 있다.
        //ethUsdPrices[20230627] 이 [2131511,23155,0,0] 이면 datetemp[20230627] 의 값은 2 

        if(datetemp[getYearMonthDay(block.timestamp)] == 0){ // 예 datetemp[20230627] 의 값이 2 이면 20230627 에 시작하는 날짜의 가격
            ethUsdPrices[getYearMonthDay(block.timestamp)][datetemp[getYearMonthDay(block.timestamp)]++] = _price; 
        } // 전에 불러왔던 가격이 현재 받은 가격과 다르면 ethUsdPrices 에 저장. 두개의 가격이 같으면 같은 response 를 받은 것이다.
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
        require(datetemp[getYearMonthDay(block.timestamp)] == 4, "the Eth UsdPrices are not stored"); // ethUsdPrices[startdate] 를 4까지 다 불러온뒤 시작 할 수 있다.
        depositTokens(_betting_amount); // betting_amount 만큼 해당 컨트렉트로 token 전송. Token contract 에서 approve 함수를 실행 안했으면 에러
        players[msg.sender] = Player(false,0,true,false, _betting_amount,0,false); // 플레이어 구조체 초기화
        players[msg.sender].startdate = getYearMonthDay(block.timestamp); // 플레이어의 startdate 를 저장
    }
    // 게임을 진행 시키는 함수. 예측 실패나 마지막 스테이지면 게임 종료로 true 를 반환. 예측 성공으로 계속 진행시 flase 를 반환한다.
    function  predict(BetDirection betDirection) public returns(bool){ // (true : up , false : down) 게임이 종료되면 true 를 반환한다.
        require(players[msg.sender].started == true , "game hasn't started yet"); // startGame() 함수를 실행하고 게임을 진행해야한다.
        require(players[msg.sender].finished == false, "the game is already over"); // 예측이 틀리거나 finishGame() 함수를 실행 했으면 게임을 진행할 수없다.
        if(players[msg.sender].stage == 3){ // 마지막 스테이지 일 경우 게임을 종료 시킨다. 
            players[msg.sender].finished = true;
            players[msg.sender].win = true;
            return true;
        } // 틀렸을때 게임을 종료 시킨다. ex) ethUsdPrices[20230629][2] >= ethUsdPrices[20230629][3] && up 이면 down && up 이므로 틀렸다.
        else if(ethUsdPrices[players[msg.sender].startdate][players[msg.sender].stage] >= ethUsdPrices[players[msg.sender].startdate][players[msg.sender].stage+1] && (betDirection == BetDirection.Up)){ // down && up
            players[msg.sender].finished = true;  // 예측실패로 게임이 종료된다.
            players[msg.sender].win = false; // 틀렸으므로 win = false 
            return true;
        } // 틀렸을때 게임을 종료 시킨다. ex) ethUsdPrices[20230629][2] <= ethUsdPrices[20230629][3] && down 이면 up && down 이므로 틀렸다.
        else if(ethUsdPrices[players[msg.sender].startdate][players[msg.sender].stage] <= ethUsdPrices[players[msg.sender].startdate][players[msg.sender].stage+1] && (betDirection == BetDirection.Down)){ // up && down
            players[msg.sender].finished = true;// 예측실패로 게임이 종료된다. 
            players[msg.sender].win = false; // 틀렸으므로 win = false 
            return true;
        }
        else{ // 배팅에서 이겼을때
            players[msg.sender].stage++;
            return false;
        }
    }

    // 게임을 종료 시키는 함수  predict 에서 배팅에 이겼는데도 불구하고 게임을 종료하고 싶을때 실행
    function finishGame() public{ 
        require(players[msg.sender].finished == false, "the game is already over");
        require(players[msg.sender].started == true, "game hasn't started yet");
        players[msg.sender].finished = true;
        players[msg.sender].win = true;
    }


    // 게임이 끝났을시 인출 함수
    function withdraw() public {
        require(players[msg.sender].withdrawn == false, "You have already withdrawn."); // 이미 인출되었으면 error 
        require(players[msg.sender].finished == true, "the game is not over yet"); // 게임이 종료 되어야지 인출할 수 있다.
        require(players[msg.sender].win == true); // 이겼을시 인출할 수 있다.
         // player 의 stage 만큼 token 을 보내준다. 처음에 10 token 을 배팅하고 2 stage 만큼 진행 했으면 20 토큰을 사용자에게 전송
        transferBack(payable(msg.sender), players[msg.sender].betting_amount * (players[msg.sender].stage+1));
    }

    // chainlink http request 를 보낼때 쓰이는 Link token 을 owner 에게 전송
    function withdrawLink() public onlyOwner {
        LinkTokenInterface link = LinkTokenInterface(chainlinkTokenAddress());
        require(
            link.transfer(msg.sender, link.balanceOf(address(this))),
            "Unable to transfer"
        );
    }
   
   // 해당 날짜의 UsdPrices 를 볼 수 있다. ex) getethUsdPrices[20230617] return [14904139806926,14910453234320998,14911425037456,14912637954773]
    function getethUsdPrices(uint256 _date) public view returns(uint256[4] memory ){
        return ethUsdPrices[_date];
    }

    
}