module dca::dca {
    // === Imports ===

    use sui::event;
    use sui::coin::{Coin, Self};
    use sui::clock::{Clock};
    use sui::balance::{Self, Balance};
    use sui::transfer::{public_transfer, share_object};

    use suitears::math64;

    // === Errors ===

    const ESlippage: u64 = 0;
    const EInactive: u64 = 1;
    const EInvalidTimeScale: u64 = 2;
    const EInvalidEvery: u64 = 3;
    const EInvalidTimestamp: u64 = 4;
    const ETooEarly: u64 = 5;
    const EInvalidFee: u64 = 6;
    const EMustBeTheOwner: u64 = 7;
    const EMustBeInactive: u64 = 8;

    // === Constants ===

    const MINUTE: u64 = 60;
    const HOUR: u64 = 3600; // 60 * 60
    const DAY: u64 = 86400; // 3600 * 24
    const WEEK: u64 = 604800; // 86400 * 7
    const MONTH: u64 = 2419200; // 86400 * 28 we take the lower bound 
    const MAX_FEE: u64 = 3000000; // 0.3%
    const PRECISION: u64 = 1000000000;

    // === Structs ===

    public struct DCA<phantom Input, phantom Output> has key {
        id: UID,
        /// The original owner of the funds
        owner: address,
        /// Account that gets the fee
        delegatee: address,
        /// Start timestamp determined by the Clock time of when the init
        /// transaction took place
        start_timestamp: u64,
        /// Last trade time
        last_trade_timestamp: u64,
        /// How many units of time, define in terms of time scale
        every: u64,
        /// How many orders remain to be executed
        remaining_orders: u64,
        /// Bit Flag representing the time scale
        /// 0 => seconds
        /// 1 => minutes
        /// 2 => hour
        /// 3 => day
        /// 4 => week
        /// 5 => month
        time_scale: u8,
        cooldown: u64,
        /// Balance to be invested over time. This amount can increase or decrease
        input_balance: Balance<Input>,
        amount_per_trade: u64,
        min: u64,
        max: u64,
        active: bool,
        owner_output: Balance<Output>,
        delegatee_output: Balance<Output>,
        fee_percent: u64
    }

    public struct Start<phantom Input, phantom Output> has copy, drop, store {
        every: u64,
        time_scale: u8,
        input: u64,
        dca_address: address,
        delegatee: address,
    }

    public struct Resolve<phantom Input, phantom Output> has copy, drop, store {
        fee: u64,
        input: u64,
        output: u64,
        dca_address: address,
    }

    public struct Destroy<phantom Input, phantom Output> has copy, drop, store {
        input: u64,
        owner_output: u64,
        delegatee_output: u64,
        dca_address: address,
        owner: address
    }

    // === Public-Mutative Functions ===

    public fun new<Input, Output>(
        clock: &Clock,
        coin_in: Coin<Input>,
        every: u64,
        number_of_orders: u64,
        time_scale: u8,
        min: u64,
        max: u64,
        fee_percent: u64,
        delegatee: address,
        ctx: &mut TxContext
    ): DCA<Input, Output> {
        assert!(MAX_FEE > fee_percent, EInvalidFee);
        assert_every(every, time_scale);

        let start_timestamp = timestamp_s(clock);

        let amount_per_trade = math64::div_down(coin_in.value(), number_of_orders);

        let dca = DCA<Input, Output> {
            id: object::new(ctx),
            owner: ctx.sender(),
            start_timestamp,
            last_trade_timestamp: start_timestamp,
            every,
            remaining_orders: number_of_orders,
            time_scale,
            input_balance: coin_in.into_balance(),
            amount_per_trade,
            min,
            max,
            active: true,
            cooldown: convert_to_timestamp(time_scale) * every,
            owner_output: balance::zero(),
            delegatee_output: balance::zero(),
            fee_percent,
            delegatee
        };

        event::emit(
            Start<Input, Output> {
            every,
            time_scale,
            input: dca.input_balance.value(),
            dca_address: object::id_address(&dca),
            delegatee
            }
        );

        dca
    }

    #[allow(lint(share_owned))]
    public fun share<Input, Output>(self: DCA<Input, Output>) {
        share_object(self);
    }

    public fun stop<Input, Output>(self: &mut DCA<Input, Output>, ctx: &mut TxContext) {
        assert!(ctx.sender() == self.owner, EMustBeTheOwner);
        self.active = false;
    }

    public fun destroy<Input, Output>(self: DCA<Input, Output>, ctx: &mut TxContext) {
        let DCA { 
            id,
            owner,
            delegatee,
            start_timestamp: _,
            last_trade_timestamp: _,
            every: _,
            remaining_orders: _,
            time_scale: _,
            cooldown: _,
            input_balance,
            amount_per_trade: _,
            min: _,
            max: _,
            active,
            owner_output,
            delegatee_output,
            fee_percent: _  
        } = self;

        assert!(!active, EMustBeInactive);

        let input = input_balance.value();
        let owner_output_value = owner_output.value();
        let delegatee_output_value = delegatee_output.value();

        public_transfer(coin::from_balance(owner_output, ctx), owner);
        public_transfer(coin::from_balance(delegatee_output, ctx), delegatee);

        event::emit(Destroy<Input, Output> {
            input,
            owner_output: owner_output_value,
            delegatee_output: delegatee_output_value,
            dca_address: object::uid_to_address(&id),
            owner
        });

        if (input == 0)
            input_balance.destroy_zero()
        else 
            public_transfer(coin::from_balance(input_balance, ctx), owner);

        object::delete(id);
    }

    // === Public-View Functions ===

    public fun owner<Input, Output>(self: &DCA<Input, Output>): address {
        self.owner
    }

    public fun delegatee<Input, Output>(self: &DCA<Input, Output>): address {
        self.delegatee
    }

    public fun start_timestamp<Input, Output>(self: &DCA<Input, Output>): u64 {
        self.start_timestamp
    }

    public fun last_trade_timestamp<Input, Output>(self: &DCA<Input, Output>): u64 {
        self.last_trade_timestamp
    }

    public fun every<Input, Output>(self: &DCA<Input, Output>): u64 {
        self.every
    }

    public fun remaining_orders<Input, Output>(self: &DCA<Input, Output>): u64 {
        self.remaining_orders
    }

    public fun time_scale<Input, Output>(self: &DCA<Input, Output>): u8 {
        self.time_scale
    }

    public fun cooldown<Input, Output>(self: &DCA<Input, Output>): u64 {
        self.cooldown
    }

    public fun input<Input, Output>(self: &DCA<Input, Output>): u64 {
        self.input_balance.value()
    }

    public fun amount_per_trade<Input, Output>(self: &DCA<Input, Output>): u64 {
        self.amount_per_trade
    }

    public fun min<Input, Output>(self: &DCA<Input, Output>): u64 {
        self.min
    }

    public fun max<Input, Output>(self: &DCA<Input, Output>): u64 {
        self.max
    }

    public fun active<Input, Output>(self: &DCA<Input, Output>): bool {
        self.active
    }

    public fun owner_output<Input, Output>(self: &DCA<Input, Output>): u64 {
        self.owner_output.value()
    }

    public fun delegatee_output<Input, Output>(self: &DCA<Input, Output>): u64 {
        self.delegatee_output.value()
    }

    public fun fee_percent<Input, Output>(self: &DCA<Input, Output>): u64 {
        self.fee_percent
    }

    public fun assert_every(every: u64, time_scale: u8) {
        // Depending on the time_scale the restrictions on `every` are different
        let is_ok = {
            if (time_scale == 0) { // 0 => seconds
            // Lower bound --> 30 seconds
            // Upper bound --> 59 seconds
            every >= 30 && every <= 59
            } else if (time_scale == 1) { // 1 => minutes
            // Lower bound --> 1 minute
            // Upper bound --> 59 minutes
            every >= 1 && every <= 59
            } else if (time_scale == 2) { // 2 => hours
            // Lower bound --> 1 hour
            // Upper bound --> 24 hours
            every >= 1 && every <= 24
            } else if (time_scale == 3) { // 3 => days
            // Lower bound --> 1 day
            // Upper bound --> 6 days
            every >= 1 && every <= 6
            } else if (time_scale == 4) { // 4 => weeks
            // Lower bound --> 1 week
            // Upper bound --> 4 weeks
            every >= 1 && every <= 4
            } else if (time_scale == 5) { // 5 => months
            // Lower bound --> 1 month
            // Upper bound --> 12 months
            every >= 1 && every <= 12
            } else {
            abort EInvalidTimeScale
            }
        };

        assert!(is_ok, EInvalidEvery);
    }

    // === Public-Friend Functions ===

    public(package) fun resolve<Input, Output>(
        self: &mut DCA<Input, Output>,
        clock: &Clock,
        coin_out: Coin<Output>
    ) {
        assert!(self.active, EInactive);

        let current_timestamp = timestamp_s(clock);

        assert!(current_timestamp - self.last_trade_timestamp >= self.cooldown, ETooEarly);

        self.last_trade_timestamp = current_timestamp;

        let output_value = coin_out.value();

        assert!(output_value >= self.min && self.max >= output_value, ESlippage);

        self.remaining_orders = self.remaining_orders - 1;

        if (self.remaining_orders == 0 || self.input_balance.value() == 0)
            self.active = false;

        let mut balance_out = coin::into_balance(coin_out);  

        let balance_fee = balance_out.split(math64::mul_div_up(output_value, self.fee_percent, PRECISION));

        event::emit(
            Resolve<Input, Output> {
            fee: balance_fee.value(),
            input: self.amount_per_trade,
            output: output_value,
            dca_address: object::id_address(self)
            }
        );

        self.delegatee_output.join(balance_fee);
        self.owner_output.join(balance_out);
    }

    public(package) fun take<Input, Output>(self: &mut DCA<Input, Output>, ctx: &mut TxContext): Coin<Input> {
        let value = self.input_balance.value();
        coin::take(&mut self.input_balance, math64::min(self.amount_per_trade, value), ctx)
    }

    // === Private Functions ===

    fun convert_to_timestamp(time_scale: u8): u64 {
        if (time_scale == 0) return 1;

        if (time_scale == 1) return MINUTE;

        if (time_scale == 2) return HOUR;

        if (time_scale == 3) return DAY;

        if (time_scale == 4) return WEEK;

        if (time_scale == 5) return MONTH;

        abort EInvalidTimestamp
        }

        fun timestamp_s(clock: &Clock): u64 {
        clock.timestamp_ms() / 1000
    }
}