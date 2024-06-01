#[test_only]
module dca::trade_policy_tests {
    use std::type_name;

    use sui::sui::SUI;
    use sui::clock::{Self, Clock};
    use sui::test_utils::{destroy, assert_eq};
    use sui::coin::{mint_for_testing, burn_for_testing};
    use sui::test_scenario::{Self, next_tx, Scenario};

    use dca::dca;
    use dca::trade_policy::{Self, TradePolicy, Admin};

    // Time scale
    const MIN: u8 = 1;

    const MINUTE: u64 = 60 * 1000;

    const ADMIN: address = @0x5;
    const OWNER: address = @0x7;
    const DELEGATEE: address = @0x8;

    public struct USDC has drop {}
    public struct Whitelisted has drop {}
    public struct Blacklisted has drop {}

    #[test]
    fun test_request() {
        let (mut scenario, clock) = set_up();

        let scenario_mut = &mut scenario;

        scenario_mut.next_tx(OWNER);

        let trade_policy = test_scenario::take_shared<TradePolicy>(scenario_mut);

        let mut dca = dca::new<SUI, USDC>(
            &clock, 
            mint_for_testing(1000, scenario.ctx()),
            2,
            2,
            MIN,
            0,
            10_000,
            0,
            DELEGATEE, 
            scenario.ctx()
        );

        let (request, sui_coin) = trade_policy.request(&mut dca, scenario.ctx());

        assert_eq(burn_for_testing(sui_coin), 500);
        assert_eq(trade_policy.whitelist(), vector[]);
        assert_eq(request.dca_address(), object::id_address(&dca));
        assert_eq(request.rule(), option::none());
        assert_eq(request.output(), 0);

        destroy(dca);
        destroy(request);
        destroy(clock);
        destroy(trade_policy);
        scenario.end();
    }

    #[test]
    fun test_add() {
        let (mut scenario, clock) = set_up_with_wit();

        let scenario_mut = &mut scenario;

        scenario_mut.next_tx(OWNER);

        let trade_policy = test_scenario::take_shared<TradePolicy>(scenario_mut);

        let mut dca = dca::new<SUI, USDC>(
            &clock, 
            mint_for_testing(1000, scenario.ctx()),
            2,
            2,
            MIN,
            0,
            10_000,
            0,
            DELEGATEE, 
            scenario.ctx()
        );

        let (mut request, sui_coin) = trade_policy.request(&mut dca, scenario.ctx());

        request.add(Whitelisted {}, mint_for_testing(3_000, scenario.ctx()));

        assert_eq(request.rule(), option::some(type_name::get<Whitelisted>()));
        assert_eq(request.output(), 3_000);

        destroy(dca);
        destroy(clock);
        destroy(request);
        destroy(sui_coin);
        destroy(trade_policy);
        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = trade_policy::ERuleAlreadyAdded)]
    fun test_add_rule_already_added_error() {
        let (mut scenario, clock) = set_up_with_wit();

        let scenario_mut = &mut scenario;

        scenario_mut.next_tx(OWNER);

        let trade_policy = test_scenario::take_shared<TradePolicy>(scenario_mut);

        let mut dca = dca::new<SUI, USDC>(
            &clock, 
            mint_for_testing(1000, scenario.ctx()),
            2,
            2,
            MIN,
            0,
            10_000,
            0,
            DELEGATEE, 
            scenario.ctx()
        );

        let (mut request, sui_coin) = trade_policy.request(&mut dca, scenario.ctx());

        request.add(Whitelisted {}, mint_for_testing(3_000, scenario.ctx()));
        request.add(Whitelisted {}, mint_for_testing(3_000, scenario.ctx()));

        destroy(dca);
        destroy(clock);
        destroy(request);
        destroy(sui_coin);
        destroy(trade_policy);
        scenario.end();
    }

    #[test]
    fun test_confirm() {
        let (mut scenario, mut clock) = set_up_with_wit();

        let scenario_mut = &mut scenario;

        scenario_mut.next_tx(OWNER);

        let trade_policy = test_scenario::take_shared<TradePolicy>(scenario_mut);

        let mut dca = dca::new<SUI, USDC>(
            &clock, 
            mint_for_testing(1000, scenario.ctx()),
            2,
            2,
            MIN,
            0,
            10_000,
            1000000,
            DELEGATEE, 
            scenario.ctx()
        );

        let (mut request, sui_coin) = trade_policy.request(&mut dca, scenario.ctx());

        request.add(Whitelisted {}, mint_for_testing(3_000, scenario.ctx()));

        clock.increment_for_testing(2 * MINUTE);

        assert_eq(dca.owner_output(), 0);
        assert_eq(dca.remaining_orders(), 2);
        assert_eq(dca.delegatee_output(), 0); 

        trade_policy::confirm(&mut dca, &clock, request);

        assert_eq(dca.owner_output(), 2997);
        assert_eq(dca.remaining_orders(), 1);
        assert_eq(dca.delegatee_output(), 3); 

        destroy(dca);
        destroy(clock);
        destroy(sui_coin);
        destroy(trade_policy);
        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = trade_policy::EInvalidDcaAddress)]
    fun test_confirm_invalid_dca_address_error() {
        let (mut scenario, mut clock) = set_up_with_wit();

        let scenario_mut = &mut scenario;

        scenario_mut.next_tx(OWNER);

        let trade_policy = test_scenario::take_shared<TradePolicy>(scenario_mut);

        let mut dca = dca::new<SUI, USDC>(
            &clock, 
            mint_for_testing(1000, scenario.ctx()),
            2,
            2,
            MIN,
            0,
            10_000,
            1000000,
            DELEGATEE, 
            scenario.ctx()
        );

        let mut dca2 = dca::new<SUI, USDC>(
            &clock, 
            mint_for_testing(1000, scenario.ctx()),
            2,
            2,
            MIN,
            0,
            10_000,
            1000000,
            DELEGATEE, 
            scenario.ctx()
        );

        let (mut request, sui_coin) = trade_policy.request(&mut dca, scenario.ctx());

        request.add(Whitelisted {}, mint_for_testing(3_000, scenario.ctx()));

        clock.increment_for_testing(2 * MINUTE);

        trade_policy::confirm(&mut dca2, &clock, request);

        destroy(dca);
        destroy(dca2);
        destroy(clock);
        destroy(sui_coin);
        destroy(trade_policy);
        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = trade_policy::EMustHaveARule)]
    fun test_confirm_must_have_a_rule_error() {
        let (mut scenario, mut clock) = set_up_with_wit();

        let scenario_mut = &mut scenario;

        scenario_mut.next_tx(OWNER);

        let trade_policy = test_scenario::take_shared<TradePolicy>(scenario_mut);

        let mut dca = dca::new<SUI, USDC>(
            &clock, 
            mint_for_testing(1000, scenario.ctx()),
            2,
            2,
            MIN,
            0,
            10_000,
            1000000,
            DELEGATEE, 
            scenario.ctx()
        );

        let (request, sui_coin) = trade_policy.request(&mut dca, scenario.ctx());

        clock.increment_for_testing(2 * MINUTE);

        trade_policy::confirm(&mut dca, &clock, request);

        destroy(dca);
        destroy(clock);
        destroy(sui_coin);
        destroy(trade_policy);
        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = trade_policy::EInvalidRule)]
    fun test_confirm_invalid_rule_error() {
        let (mut scenario, mut clock) = set_up_with_wit();

        let scenario_mut = &mut scenario;

        scenario_mut.next_tx(OWNER);

        let trade_policy = test_scenario::take_shared<TradePolicy>(scenario_mut);

        let mut dca = dca::new<SUI, USDC>(
            &clock, 
            mint_for_testing(1000, scenario.ctx()),
            2,
            2,
            MIN,
            0,
            10_000,
            1000000,
            DELEGATEE, 
            scenario.ctx()
        );

        let (mut request, sui_coin) = trade_policy.request(&mut dca, scenario.ctx());

        clock.increment_for_testing(2 * MINUTE);

        request.add(Blacklisted {}, mint_for_testing(3_000, scenario.ctx()));

        trade_policy::confirm(&mut dca, &clock, request);

        destroy(dca);
        destroy(clock);
        destroy(sui_coin);
        destroy(trade_policy);
        scenario.end();
    }

    #[test]
    fun test_disapprove() {
        let (mut scenario, clock) = set_up_with_wit();

        let scenario_mut = &mut scenario;

        next_tx(scenario_mut, ADMIN);

        let admin_cap = test_scenario::take_from_sender<Admin>(scenario_mut);
        let mut trade_policy = test_scenario::take_shared<TradePolicy>(scenario_mut);

        assert_eq(trade_policy.whitelist(), vector[type_name::get<Whitelisted>()]);

        trade_policy::disapprove<Whitelisted>(&admin_cap, &mut trade_policy);

        assert_eq(trade_policy.whitelist(), vector[]);

        destroy(admin_cap);
        destroy(clock);
        destroy(trade_policy);
        scenario.end(); 
    }

    fun set_up(): (Scenario, Clock) {
        let mut scenario = test_scenario::begin(ADMIN);

        trade_policy::init_for_testing(scenario.ctx());

        let clock = clock::create_for_testing(scenario.ctx());

        (scenario, clock)
    } 

    fun set_up_with_wit(): (Scenario, Clock) {
        let mut scenario = test_scenario::begin(ADMIN);

        trade_policy::init_for_testing(scenario.ctx());

        let clock = clock::create_for_testing(scenario.ctx());

        next_tx(&mut scenario, ADMIN);

        let mut trade_policy = test_scenario::take_shared<TradePolicy>(&scenario);
        let admin_cap = test_scenario::take_from_sender<Admin>(&scenario);

        trade_policy::approve<Whitelisted>(&admin_cap, &mut trade_policy);

        test_scenario::return_shared(trade_policy);
        scenario.return_to_sender(admin_cap);

        (scenario, clock)
    }  
}