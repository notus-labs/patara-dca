#[test_only]
module dca::dca_tests {

    use sui::clock;
    use sui::sui::SUI;
    use sui::test_utils::{destroy, assert_eq};
    use sui::tx_context::{new_from_hint};
    use sui::coin::{mint_for_testing, burn_for_testing, Coin};
    use sui::test_scenario::{Self, take_from_address, next_tx};

    use dca::dca;

    // Time scale
    const MIN: u8 = 1;

    const MINUTE: u64 = 60;
    const MAX_FEE: u64 = 3000000; // 3%

    const MILLISECONDS: u64 = 1000;
    const MAX_U64: u64 = 18446744073709551615;

    const OWNER: address = @0x7;
    const DELEGATEE: address = @0x8;

    public struct USDC has drop {}

    #[test]
    fun test_new() {
        let ctx_mut = &mut ctx();
        let mut clock = clock::create_for_testing(ctx_mut);

        clock.increment_for_testing(15 * MILLISECONDS);

        let coin_in_value = 100;
        let every = 3;
        let number_of_orders = 10;
        let min = 1;
        let max = 2;
        let fee_percent = 77;

        let dca = dca::new<SUI, USDC>(
            &clock,
            mint_for_testing<SUI>(coin_in_value, ctx_mut),
            every,
            number_of_orders,
            MIN,
            min,
            max,
            fee_percent,
            DELEGATEE,
            ctx_mut
        );

        assert_eq(dca.owner(), OWNER);
        assert_eq(dca.delegatee(), DELEGATEE);
        assert_eq(dca.start_timestamp(), 15);
        assert_eq(dca.last_trade_timestamp(), 15);
        assert_eq(dca.time_scale(), MIN);
        assert_eq(dca.amount_per_trade(), 100 / number_of_orders);
        assert_eq(dca.min(), min);
        assert_eq(dca.max(), max);
        assert_eq(dca.active(), true);
        assert_eq(dca.cooldown(), MINUTE * every);
        assert_eq(dca.input(), 100);
        assert_eq(dca.owner_output(), 0);
        assert_eq(dca.delegatee_output(), 0);
        assert_eq(dca.fee_percent(), fee_percent);
        assert_eq(dca.remaining_orders(), 10);

        destroy(dca);
        destroy(clock);
    }

    #[test]
    #[expected_failure(abort_code = dca::EInvalidFee)]
    fun test_new_invalid_fee() {
        let ctx_mut = &mut ctx();
        let clock = clock::create_for_testing(ctx_mut);

        let coin_in_value = 100;
        let every = 3;
        let number_of_orders = 10;
        let min = 1;
        let max = 2;

        let dca = dca::new<SUI, USDC>(
            &clock,
            mint_for_testing<SUI>(coin_in_value, ctx_mut),
            every,
            number_of_orders,
            MIN,
            min,
            max,
            MAX_FEE,
            DELEGATEE,
            ctx_mut
        );

        destroy(dca);
        destroy(clock);
    }

    #[test]
    fun test_resolve() {
        let ctx_mut = &mut ctx();
        let mut clock = clock::create_for_testing(ctx_mut);

        let mut dca = dca::new<SUI, USDC>(
            &clock,
            mint_for_testing<SUI>(100, ctx_mut),
            2,
            2,
            MIN,
            0,
            MAX_U64,
            1000000,
            DELEGATEE,
            ctx_mut
        ); 

        clock.increment_for_testing(2 * MINUTE * MILLISECONDS);

        assert_eq(dca.active(), true); 
        assert_eq(dca.remaining_orders(), 2);

        dca.resolve(
            &clock,
            mint_for_testing<USDC>(2000, ctx_mut)
        );

        assert_eq(dca.active(), true); 
        assert_eq(dca.owner_output(), 1998);
        assert_eq(dca.remaining_orders(), 1);
        assert_eq(dca.delegatee_output(), 2);

        clock.increment_for_testing(2 * MINUTE * MILLISECONDS);

        dca.resolve(
            &clock,
            mint_for_testing<USDC>(3000, ctx_mut)
        );

        assert_eq(dca.active(), false); 
        assert_eq(dca.owner_output(), 4995);
        assert_eq(dca.remaining_orders(), 0);
        assert_eq(dca.delegatee_output(), 5);   

        destroy(dca);
        destroy(clock);
    }

    #[test]
    #[expected_failure(abort_code = dca::EInactive)]
    fun test_resolve_inactive_error() {
        let ctx_mut = &mut ctx();
        let mut clock = clock::create_for_testing(ctx_mut);

        let mut dca = dca::new<SUI, USDC>(
            &clock,
            mint_for_testing<SUI>(100, ctx_mut),
            2,
            2,
            MIN,
            0,
            MAX_U64,
            1000000,
            DELEGATEE,
            ctx_mut
        ); 

        clock.increment_for_testing(2 * MINUTE * MILLISECONDS);

        dca.stop(ctx_mut);

        assert_eq(dca.active(), false); 
        assert_eq(dca.remaining_orders(), 2);

        dca.resolve(
            &clock,
            mint_for_testing<USDC>(2000, ctx_mut)
        );

        destroy(dca);
        destroy(clock);
    }

    #[test]
    #[expected_failure(abort_code = dca::ETooEarly)]
    fun test_resolve_too_early_error() {
        let ctx_mut = &mut ctx();
        let mut clock = clock::create_for_testing(ctx_mut);

        let mut dca = dca::new<SUI, USDC>(
            &clock,
            mint_for_testing<SUI>(100, ctx_mut),
            2,
            2,
            MIN,
            0,
            MAX_U64,
            1000000,
            DELEGATEE,
            ctx_mut
        ); 

        clock.increment_for_testing((2 * MINUTE * MILLISECONDS) - 1);

        dca.resolve(
            &clock,
            mint_for_testing<USDC>(2000, ctx_mut)
        );

        destroy(dca);
        destroy(clock);
    }

    #[test]
    #[expected_failure(abort_code = dca::ESlippage)]
    fun test_resolve_min_slippage_error() {
        let ctx_mut = &mut ctx();
        let mut clock = clock::create_for_testing(ctx_mut);

        let mut dca = dca::new<SUI, USDC>(
            &clock,
            mint_for_testing<SUI>(100, ctx_mut),
            2,
            2,
            MIN,
            2001,
            MAX_U64,
            1000000,
            DELEGATEE,
            ctx_mut
        ); 

        clock.increment_for_testing((2 * MINUTE * MILLISECONDS));

        dca.resolve(
            &clock,
            mint_for_testing<USDC>(2000, ctx_mut)
        );

        destroy(dca);
        destroy(clock);
    }

    #[test]
    #[expected_failure(abort_code = dca::ESlippage)]
    fun test_resolve_max_slippage_error() {
        let ctx_mut = &mut ctx();
        let mut clock = clock::create_for_testing(ctx_mut);

        let mut dca = dca::new<SUI, USDC>(
            &clock,
            mint_for_testing<SUI>(100, ctx_mut),
            2,
            2,
            MIN,
            100,
            1999,
            1000000,
            DELEGATEE,
            ctx_mut
        ); 

        clock.increment_for_testing((2 * MINUTE * MILLISECONDS));

        dca.resolve(
            &clock,
            mint_for_testing<USDC>(2000, ctx_mut)
        );

        destroy(dca);
        destroy(clock);
    }

    #[test]
    fun test_take() {
        let ctx_mut = &mut ctx();
        let clock = clock::create_for_testing(ctx_mut);

        let mut dca = dca::new<SUI, USDC>(
            &clock,
            mint_for_testing<SUI>(100, ctx_mut),
            2,
            2,
            MIN,
            0,
            MAX_U64,
            1000000,
            DELEGATEE,
            ctx_mut
        ); 

        assert_eq(burn_for_testing(dca.take(ctx_mut)), 50);
        assert_eq(burn_for_testing(dca.take(ctx_mut)), 50);
        assert_eq(burn_for_testing(dca.take(ctx_mut)), 0); 

        destroy(dca);
        destroy(clock);  
    }

    #[test]
    fun test_destroy() {
        let mut _scenario = test_scenario::begin(OWNER);
        let scenario = &mut _scenario;

        let mut clock = clock::create_for_testing(scenario.ctx());

        let mut dca = dca::new<SUI, USDC>(
            &clock,
            mint_for_testing<SUI>(100, scenario.ctx()),
            2,
            2,
            MIN,
            0,
            MAX_U64,
            1000000,
            DELEGATEE,
            scenario.ctx()
        ); 

        clock.increment_for_testing(2 * MINUTE * MILLISECONDS);

        dca.resolve(
            &clock,
            mint_for_testing<USDC>(2000, scenario.ctx())
        );

        next_tx(scenario, OWNER);

        clock.increment_for_testing(2 * MINUTE * MILLISECONDS);

        dca.resolve(
            &clock,
            mint_for_testing<USDC>(3000, scenario.ctx())
        ); 

        dca.destroy(scenario.ctx());

        next_tx(scenario, OWNER);

        let owner_coin = take_from_address<Coin<USDC>>(scenario, OWNER);
        let delegatee_coin = take_from_address<Coin<USDC>>(scenario, DELEGATEE);

        assert_eq(burn_for_testing(owner_coin), 4995);
        assert_eq(burn_for_testing(delegatee_coin), 5);

        destroy(clock);  
        _scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = dca::EMustBeTheOwner)] 
    fun test_stop_must_be_owner_error() {
        let ctx_mut = &mut ctx();
        let clock = clock::create_for_testing(ctx_mut);

        let mut dca = dca::new<SUI, USDC>(
            &clock,
            mint_for_testing<SUI>(100, ctx_mut),
            2,
            2,
            MIN,
            100,
            1999,
            1000000,
            DELEGATEE,
            ctx_mut
        );   

        dca.stop(
            &mut new_from_hint(
                @0x9, 
                7, 
                0, 
                0, 
                0
            )
        );

        destroy(dca);
        destroy(clock); 
    }

    #[test]
    #[expected_failure(abort_code = dca::EMustBeInactive)] 
    fun test_stop_must_be_inactive_error() {
        let ctx_mut = &mut ctx();
        let clock = clock::create_for_testing(ctx_mut);

        let dca = dca::new<SUI, USDC>(
            &clock,
            mint_for_testing<SUI>(100, ctx_mut),
            2,
            2,
            MIN,
            100,
            1999,
            1000000,
            DELEGATEE,
            ctx_mut
        );   

        dca.destroy(ctx_mut);
        destroy(clock); 
    }

    fun ctx(): TxContext {
        let ctx = new_from_hint(
            OWNER, 
            7, 
            0, 
            0, 
            0
        );

        ctx
    }
}