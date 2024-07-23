var { VOID_ETHEREUM_ADDRESS, abi, VOID_BYTES32, blockchainCall, sendBlockchainTransaction, numberToString, compile, sendAsync, deployContract, abi, MAX_UINT256, web3Utils, fromDecimals, toDecimals } = global.multiverse = require('@ethereansos/multiverse');

var additionalData = { from : web3.currentProvider.knowledgeBase.from, bypassGasEstimation : !process.env.PRODUCTION };

var fs = require('fs');
var path = require('path');

var deadAddress = "0xdeaDDeADDEaDdeaDdEAddEADDEAdDeadDEADDEaD";

function _calculatePercentage(totalAmount, percentage) {
    var FULL_PRECISION = web3Utils.toBN(numberToString(1e18));
    return totalAmount.mul(percentage.mul(FULL_PRECISION).div(FULL_PRECISION)).div(FULL_PRECISION);
}

async function deployVestingContract(bootstrapStarts) {

    var owners = [];
    var amounts = [];
    (global.vestings = global.vestings || [])[0].owners.forEach((it, i) => {
        owners.push(it);
        var amount = _calculatePercentage(web3Utils.toBN(global.vestings[0].amounts[i]), web3Utils.toBN(toDecimals(0.2, 18))).toString();
        amounts.push(amount);
        global.vestings[0].amounts[i] = global.vestings[0].amounts[i].ethereansosSub(amount);
    })

    var VestingContract = await compile('VestingContract');

    var vestingContract = await deployContract(new web3.eth.Contract(VestingContract.abi), VestingContract.bin, [VOID_ETHEREUM_ADDRESS, global.vestings = (global.vestings || []).map(it => ({...it, info : {...it.info, startingFrom : it.info.startingFrom + bootstrapStarts}}))], {...additionalData, bypassGasEstimation : !process.env.PRODUCTION});

    var i = 0;
    while(true) {
        try {
            var info = await vestingContract.methods.infos(i++).call();
            if(info.startingFrom === '0') {
                break;
            }
            console.log('Starting from:', new Date(parseInt(info.startingFrom) * 1000).toLocaleString());
        } catch(e) {
            break;
        }
    }

    var amount = '0';

    for(var vesting of vestings) {
        for(var amt of vesting.amounts) {
            amount = amount.ethereansosAdd(amt);
        }
    }

    return {
        vestings,
        contract : vestingContract,
        address : vestingContract.options.address,
        amount,
        owners,
        amounts
    };
}

function splitAmount(receivers, totalAmount) {
    var amounts = receivers.map(() => '0');
    var percentages = amounts.map(() => Math.random() * (0.9999 - 0.0001) + 0.0001);
    var sum = percentages.reduce((acc, it) => acc + it, 0);
    percentages = percentages.map(it => it / sum);
    sum = '0';
    for(var z = 0; z < amounts.length; z++) {
        sum = sum.ethereansosAdd(amounts[z] = numberToString(parseInt(totalAmount) * percentages[z]).split('.')[0]);
    }
    var diff = totalAmount.ethereansosSub(sum);
    console.log(totalAmount, sum, diff);
    if(diff !== '0') {
        amounts[amounts.length - 1] = amounts[amounts.length - 1][`ethereansos${diff.indexOf('-') === 0 ? 'Sub' : 'Add'}`](diff.split('-').join(''));
        sum = amounts.reduce((acc, it) => acc.ethereansosAdd(it), '0');
        diff = totalAmount.ethereansosSub(sum);
        console.log(totalAmount, sum, diff);
    }
    return amounts;
}

module.exports = async function start() {

    var bootstrapStarts = new Date(process.env.BOOTSTRAP_STARTS || new Date().getTime());
    bootstrapStarts = parseInt(bootstrapStarts.getTime() / 1000);
    console.log("Bootstrap Starts", new Date(bootstrapStarts * 1000).toISOString(), new Date(bootstrapStarts * 1000).toString());

    var data = await deployVestingContract(bootstrapStarts);

    var marketingWallets = global.vestings[0].wallets.slice(300, 328).map(it => web3Utils.toChecksumAddress(it.address));

    var marketingAmounts = splitAmount(marketingWallets, toDecimals(8000000, 18));

    var whitelisted = global.vestings[0].wallets.slice(330, 360).map(it => web3Utils.toChecksumAddress(it.address));

    var distributionWallets = [
        ...data.owners,
        ...marketingWallets,
        data.address,
        "0xBA2A0A4CDb2e0c8aA842B8F3AAC59f2cB08257e0",
        "0xa35f243e756F4cFA58C562f8BAF9F83425b48c5a",
        "0xAdd68fC1eED7FaF38DD2D8629F522062C0b72fa9",
        VOID_ETHEREUM_ADDRESS
    ];
    var distributionAmounts = [
        ...data.amounts,
        ...marketingAmounts,
        data.amount,
        toDecimals(1000000, 18),
        toDecimals(1000000, 18),
        toDecimals(2000000, 18),
        toDecimals(10000000, 18)
    ];

    var sum = distributionAmounts.reduce((acc, it) => acc.ethereansosAdd(it), "0");
    var remaining = toDecimals(100000000, 18).ethereansosSub(sum);
    var lastBurnAmount = remaining.ethereansosSub(toDecimals(19000000, 18));

    var thresholds = [];
    for(var i = 0; i < 20; i++) {
        thresholds.push((toDecimals("5000000".ethereansosMul(i + 1), 6)));
    }

    thresholds = thresholds.sort((a, b) => parseInt(b) - parseInt(a));

    var burnAmounts = thresholds.map(() => toDecimals('1000000', 18));
    burnAmounts[burnAmounts.length - 1] = lastBurnAmount;
    var burnReceivers = thresholds.map(() => deadAddress);

    var teamWallet = "0x7122C9D61be7BFd0B320b23F513230f0FcECcCfA";
    var teamPercentage = toDecimals("0.6", 18);

    var tokenTaxesReceiverArgs = [
        thresholds,
        burnAmounts,
        burnReceivers,
        teamWallet,
        teamPercentage,
        web3.currentProvider.knowledgeBase.UNISWAP_V2_SWAP_ROUTER_ADDRESS,
        toDecimals("0.1", 18)
    ];

    var TokenTaxesReceiver = await compile('TokenTaxesReceiver');
    var tokenTaxesReceiver = await deployContract(new web3.eth.Contract(TokenTaxesReceiver.abi), TokenTaxesReceiver.bin, tokenTaxesReceiverArgs, additionalData);
    var taxesAddress = tokenTaxesReceiver.options.address;

    distributionWallets.push(taxesAddress);
    distributionAmounts.push(remaining);

    var tokenArgs = [
        web3.currentProvider.knowledgeBase.fromAddress,
        data.address,
        web3.currentProvider.knowledgeBase.UNISWAP_V2_SWAP_ROUTER_ADDRESS,
        VOID_ETHEREUM_ADDRESS,
        35,35,
        distributionWallets,
        distributionAmounts,
        whitelisted
    ];
    
    var Token = await compile('Token');
    var token = await deployContract(new web3.eth.Contract(Token.abi), Token.bin, tokenArgs, {...additionalData, bypassGasEstimation : !process.env.PRODUCTION, value : toDecimals('3', 18)});
    web3.currentProvider.knowledgeBase.KNS = token.options.address; 

    console.log("Total supply", fromDecimals(await token.methods.totalSupply().call(), 18));

    var UniswapV2Pair = await compile('IUniswapV2', 'IUniswapV2Pair');
    var uniswapV2PairAddress = await token.methods.uniswapV2PairAddress().call();
    var uniswapV2Pair = new web3.eth.Contract(UniswapV2Pair.abi, uniswapV2PairAddress);
    var balanceOf = await blockchainCall(uniswapV2Pair.methods.balanceOf, web3.currentProvider.knowledgeBase.fromAddress);
    balanceOf === '0' && await blockchainCall(uniswapV2Pair.methods.mint, web3.currentProvider.knowledgeBase.fromAddress, {...additionalData, bypassGasEstimation : process.env.PRODUCTION !== 'true'});

    var Quoter = await compile('@ethereans-labs/protocol/contracts/impl/UniswapV2PriceOracleQuoter');
    var quoter = await deployContract(new web3.eth.Contract(Quoter.abi), Quoter.bin, [web3.currentProvider.knowledgeBase.UNISWAP_V2_SWAP_ROUTER_ADDRESS], additionalData);

    var quoterAddress = quoter.options.address;
    var quoterPayload = abi.encode(["address[]"], [[web3.currentProvider.knowledgeBase.KNS, web3.currentProvider.knowledgeBase.WETH_ADDRESS, web3.currentProvider.knowledgeBase.USDC_TOKEN_ADDRESS]])
    var _setInterval = 180;
    var minTimeIntervalTolerance = 86400;
    var limitPercDiff = toDecimals(30, 18);
    var delayedTimestamp = 0;
    var priceOracleData = abi.encode(["address", "bytes", "uint256", "uint256", "uint256", "uint256"], [quoterAddress, quoterPayload, _setInterval, minTimeIntervalTolerance, limitPercDiff, delayedTimestamp]);
    priceOracleData = abi.encode(["address", "bytes"], [web3.currentProvider.knowledgeBase.fromAddress, priceOracleData]);

    var PriceOracle = await compile('@ethereans-labs/protocol/contracts/impl/PriceOracle');
    var priceOracle = await deployContract(new web3.eth.Contract(PriceOracle.abi), PriceOracle.bin, [priceOracleData], additionalData);

    await blockchainCall(tokenTaxesReceiver.methods.setOracle, priceOracle.options.address, additionalData);

    await blockchainCall(priceOracle.methods.setPrice, additionalData);
};

module.exports.test = async function test() {
    var Token = await compile('Token');
    var token = new web3.eth.Contract(Token.abi, web3.currentProvider.knowledgeBase.KNS);

    var Uniswap = await compile('IUniswapV2', 'IUniswapV2Router02');
    var uniswap = new web3.eth.Contract(Uniswap.abi, web3.currentProvider.knowledgeBase.UNISWAP_V2_SWAP_ROUTER_ADDRESS);
    await blockchainCall(uniswap.methods.swapExactETHForTokensSupportingFeeOnTransferTokens, 0, [web3.currentProvider.knowledgeBase.WETH_ADDRESS, token.options.address], accounts[0], new Date().getTime(), { from : accounts[0], value : toDecimals("8", 18)})
    await blockchainCall(token.methods.approve, web3.currentProvider.knowledgeBase.UNISWAP_V2_SWAP_ROUTER_ADDRESS, MAX_UINT256);
    await blockchainCall(uniswap.methods.swapExactTokensForTokensSupportingFeeOnTransferTokens, toDecimals("1", 18), 0, [token.options.address, web3.currentProvider.knowledgeBase.WETH_ADDRESS], accounts[0], new Date().getTime(), { from : accounts[0]})
}