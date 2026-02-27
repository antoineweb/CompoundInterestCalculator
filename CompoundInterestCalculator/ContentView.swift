import SwiftUI
import Charts

// MARK: - Models

enum Currency: String, CaseIterable, Identifiable {
    case usd = "$"
    case eur = "€"
    case gbp = "£"
    case inr = "₹"
    case jpy = "¥"
    case aed = "د.إ"
    case thb = "฿"
    var id: String { rawValue }
}

enum CompoundFrequency: String, CaseIterable, Identifiable {
    case yearly = "Yearly (1/yr)"
    case quarterly = "Quarterly (4/yr)"
    case monthly = "Monthly (12/yr)"
    case daily = "Daily (365/yr)"
    var id: String { rawValue }
    var periodsPerYear: Int {
        switch self {
        case .yearly: return 1
        case .quarterly: return 4
        case .monthly: return 12
        case .daily: return 365
        }
    }
}

struct YearBreakdown: Identifiable {
    let id = UUID()
    let year: Int
    let interest: Double
    let accruedInterest: Double
    let balance: Double
}

// MARK: - ViewModel

class CompoundInterestViewModel: ObservableObject {
    @Published var currency: Currency = .usd
    @Published var initialInvestment: String = "5000"
    @Published var interestRate: String = "5"
    @Published var compoundFrequency: CompoundFrequency = .monthly
    @Published var years: Int = 5
    @Published var months: Int = 0
    @Published var monthlyDeposit: String = ""
    @Published var annualDepositIncrease: String = ""
    
    // Results
    @Published var finalValue: Double = 0
    @Published var totalInterest: Double = 0
    @Published var timeToDouble: String = ""
    @Published var breakdown: [YearBreakdown] = []
    
    // Interactive chart state
    @Published var selectedDataPoint: Int? = nil
    
    func calculate() {
        let P = Double(initialInvestment) ?? 0
        let r = (Double(interestRate) ?? 0) / 100
        let n = Double(compoundFrequency.periodsPerYear)
        let t = Double(years) + Double(months) / 12.0
        let PMT = Double(monthlyDeposit) ?? 0
        let annualIncrease = (Double(annualDepositIncrease) ?? 0) / 100
        
        // Compound interest with contributions
        var balance = P
        var accruedInterest = 0.0
        var yearlyBreakdown: [YearBreakdown] = []
        var currentDeposit = PMT
        let periods = Int(n * t)
        let periodsPerYear = Int(n)
        var interestThisYear = 0.0
        var year = 0
        var balances: [Double] = [P]
        
        for period in 1...periods {
            let interest = balance * (r / n)
            balance += interest
            accruedInterest += interest
            interestThisYear += interest
            
            // Add deposit at end of period (monthly, quarterly, etc.)
            if PMT > 0 {
                balance += currentDeposit
            }
            
            // Increase deposit annually if set
            if period % periodsPerYear == 0 && PMT > 0 && annualIncrease > 0 {
                currentDeposit *= (1 + annualIncrease)
            }
            
            // End of year breakdown
            if period % periodsPerYear == 0 || period == periods {
                year += 1
                yearlyBreakdown.append(
                    YearBreakdown(
                        year: year,
                        interest: interestThisYear,
                        accruedInterest: accruedInterest,
                        balance: balance
                    )
                )
                interestThisYear = 0
                balances.append(balance)
            }
        }
        
        // Final values
        finalValue = balance
        totalInterest = accruedInterest
        breakdown = yearlyBreakdown
        
        // Time to double investment
        timeToDouble = calculateTimeToDouble(P: P, r: r, n: n, PMT: PMT, annualIncrease: annualIncrease)
    }
    
    private func calculateTimeToDouble(P: Double, r: Double, n: Double, PMT: Double, annualIncrease: Double) -> String {
        // For no contributions, use log formula
        if PMT == 0 {
            let t = log(2) / (n * log(1 + r / n))
            let years = Int(t)
            let months = Int((t - Double(years)) * 12)
            return "\(years) years, \(months) months"
        } else {
            // With contributions, simulate until doubled
            let target = P * 2
            var balance = P
            var currentDeposit = PMT
            var periods = 0
            let periodsPerYear = Int(n)
            while balance < target && periods < 100*Int(n) {
                let interest = balance * (r / n)
                balance += interest
                if PMT > 0 {
                    balance += currentDeposit
                }
                periods += 1
                if periods % periodsPerYear == 0 && PMT > 0 && annualIncrease > 0 {
                    currentDeposit *= (1 + annualIncrease)
                }
            }
            let years = periods / periodsPerYear
            let months = Int(Double(periods % periodsPerYear) / Double(periodsPerYear) * 12)
            return "\(years) years, \(months) months"
        }
    }
    
    // Formatters
    func currencyString(_ value: Double) -> String {
        let roundedValue = (value * 10).rounded() / 10 // round to 1 decimal
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencySymbol = currency.rawValue
        formatter.maximumFractionDigits = 0
        formatter.minimumFractionDigits = 0
        formatter.locale = Locale(identifier: "en_US")
        if let str = formatter.string(from: NSNumber(value: roundedValue)) {
            return str.replacingOccurrences(of: "\u{00a0}", with: "")
        }
        return "\(currency.rawValue)\(String(format: "%.1f", roundedValue))"
    }
    
    
    func percentString(_ value: Double) -> String {
        String(format: "%.2f%%", value)
    }
    
    // MARK: - Interactive Chart Methods
    
    /// Update initial investment based on clicked point at the beginning (year 1)
    func setInitialInvestmentFromChart(targetBalance: Double) {
        initialInvestment = String(Int(targetBalance.rounded()))
        calculate()
    }
    
    /// Calculate required interest rate to reach target balance at the end
    func setInterestRateFromFinalBalance(targetBalance: Double) {
        let P = Double(initialInvestment) ?? 1000
        let t = Double(years) + Double(months) / 12.0
        let n = Double(compoundFrequency.periodsPerYear)
        
        if P == 0 { return }
        
        // Using compound interest formula: A = P(1 + r/n)^(nt)
        // We need to find r
        let ratio = targetBalance / P
        let exponent = n * t
        
        // r/n = ratio^(1/exponent) - 1
        let ratePerPeriod = pow(ratio, 1.0 / exponent) - 1
        let annualRate = (ratePerPeriod * n) * 100
        
        // Clamp to reasonable values
        let clampedRate = max(0.01, min(100.0, annualRate))
        interestRate = String(format: "%.2f", clampedRate)
        calculate()
    }
}

// MARK: - Views

struct ContentView: View {
    @StateObject private var vm = CompoundInterestViewModel()
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Input Card
                    InputBlock(vm: vm)
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color(.systemBackground))
                                .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 2)
                        )
                        .padding(.horizontal)
                    
                    // Results Card
                    ResultsBlock(vm: vm)
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color(.systemBackground))
                                .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 2)
                        )
                        .padding(.horizontal)
                    
                    // Growth Chart
                    if !vm.breakdown.isEmpty {
                        GrowthChartBlock(vm: vm)
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(Color(.systemBackground))
                                    .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 2)
                            )
                            .padding(.horizontal)
                    }

                    // Breakdown Table
                    BreakdownBlock(vm: vm)
                        .padding(.horizontal)
                }
                .padding(.vertical)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Compound Interest")
            .onAppear { vm.calculate() }
        }
    }
}

struct InputBlock: View {
    @ObservedObject var vm: CompoundInterestViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Currency Selector
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Currency.allCases) { currency in
                        Button(action: {
                            vm.currency = currency
                            vm.calculate()
                        }) {
                            Text(currency.rawValue)
                                .font(.headline)
                                .foregroundColor(vm.currency == currency ? .white : .primary)
                                .frame(width: 40, height: 40)
                                .background(vm.currency == currency ? Color.orange : Color(.systemGray5))
                                .clipShape(Circle())
                        }
                    }
                }
            }
            
            // Initial Investment
            InputField(title: "Initial investment", value: $vm.initialInvestment, prefix: vm.currency.rawValue, keyboardType: .decimalPad)
            
            // Interest Rate
            HStack {
                InputField(title: "Interest rate", value: $vm.interestRate, suffix: "%", keyboardType: .decimalPad)
                Picker("", selection: .constant("annual")) {
                    Text("annual").tag("annual")
                }
                .pickerStyle(MenuPickerStyle())
                .frame(width: 80)
                .disabled(true)
            }
            
            // Compound Frequency
            Picker("Compound frequency", selection: $vm.compoundFrequency) {
                ForEach(CompoundFrequency.allCases) { freq in
                    Text(freq.rawValue).tag(freq)
                }
            }
            .pickerStyle(MenuPickerStyle())
            
            // Duration
            HStack {
                Stepper(value: $vm.years, in: 0...100) {
                    HStack {
                        Text("Years")
                        Spacer()
                        Text("\(vm.years)")
                    }
                }
                Stepper(value: $vm.months, in: 0...11) {
                    HStack {
                        Text("Months")
                        Spacer()
                        Text("\(vm.months)")
                    }
                }
            }
            
            // Additional Contributions
            VStack(alignment: .leading, spacing: 8) {
                Text("Additional contributions (optional)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                InputField(title: "Deposit amount", value: $vm.monthlyDeposit, prefix: vm.currency.rawValue, keyboardType: .decimalPad)
                HStack {
                    Text("monthly")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                InputField(title: "Annual deposit % increase (optional)", value: $vm.annualDepositIncrease, suffix: "%", keyboardType: .decimalPad)
            }
            
            // Calculate Button
            Button(action: { vm.calculate() }) {
                HStack {
                    Spacer()
                    Text("Calculate")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding()
                    Spacer()
                }
                .background(Color.green)
                .cornerRadius(8)
            }
            .padding(.top, 8)
        }
    }
}

struct InputField: View {
    let title: String
    @Binding var value: String
    var prefix: String? = nil
    var suffix: String? = nil
    var keyboardType: UIKeyboardType = .default
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            HStack {
                if let prefix = prefix {
                    Text(prefix)
                        .foregroundColor(.secondary)
                }
                TextField("", text: $value)
                    .keyboardType(keyboardType)
                    .textFieldStyle(PlainTextFieldStyle())
                    .frame(minWidth: 60)
                if let suffix = suffix {
                    Text(suffix)
                        .foregroundColor(.secondary)
                }
            }
            .padding(8)
            .background(Color(.systemGray6))
            .cornerRadius(6)
        }
    }
}

struct ResultsBlock: View {
    @ObservedObject var vm: CompoundInterestViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Interest calculation for \(vm.years) years\(vm.months > 0 ? ", \(vm.months) months" : "")")
                .font(.headline)
                .foregroundColor(.orange)
            
            HStack(spacing: 24) {
                VStack(alignment: .leading) {
                    Text("Future investment value")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(vm.currencyString(vm.finalValue))
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundColor(.green)
                }
                VStack(alignment: .leading) {
                    Text("Total interest earned")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(vm.currencyString(vm.totalInterest))
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.orange)
                }
                VStack(alignment: .leading) {
                    Text("Initial balance")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(vm.currencyString(Double(vm.initialInvestment) ?? 0))
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.blue)
                }
            }
            
            Divider()
            
            HStack {
                VStack(alignment: .leading) {
                    Text("Time needed to double investment")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(vm.timeToDouble)
                        .font(.headline)
                        .foregroundColor(.primary)
                }
                Spacer()
            }
        }
    }
}

struct GrowthChartBlock: View {
    @ObservedObject var vm: CompoundInterestViewModel
    @State private var targetBalance: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Interactive Growth Chart")
                    .font(.headline)
                    .foregroundColor(.orange)
                Text("Tap the starting point to change initial investment, or the ending point to set target balance")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if !vm.breakdown.isEmpty {
                ZStack {
                    // Chart background
                    Chart {
                        // Balance line
                        ForEach(vm.breakdown) { row in
                            LineMark(
                                x: .value("Year", row.year),
                                y: .value("Balance", row.balance)
                            )
                            .foregroundStyle(Color.green.opacity(0.7))
                            .symbol(Circle())
                            .interpolationMethod(.catmullRom)
                        }

                        // Principal + deposits baseline
                        let principal = Double(vm.initialInvestment) ?? 0
                        let deposit = Double(vm.monthlyDeposit) ?? 0
                        ForEach(vm.breakdown) { row in
                            let totalDeposits = principal + deposit * 12 * Double(row.year)
                            LineMark(
                                x: .value("Year", row.year),
                                y: .value("Deposits", totalDeposits)
                            )
                            .foregroundStyle(Color.blue.opacity(0.5))
                            .lineStyle(StrokeStyle(dash: [5, 3]))
                            .interpolationMethod(.catmullRom)
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading) { value in
                            AxisGridLine()
                            AxisValueLabel {
                                if let v = value.as(Double.self) {
                                    Text(vm.currencyString(v))
                                        .font(.caption2)
                                }
                            }
                        }
                    }
                    .chartXAxisLabel("Year")
                    .frame(height: 240)
                    
                    // Overlay with interactive points
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 0) {
                            // Starting point - tap to change initial investment
                            if let firstPoint = vm.breakdown.first {
                                Button(action: {
                                    vm.selectedDataPoint = 0
                                }) {
                                    VStack {
                                        Circle()
                                            .fill(vm.selectedDataPoint == 0 ? Color.red : Color.green)
                                            .frame(width: 12, height: 12)
                                        
                                        VStack(spacing: 2) {
                                            Text("Year 1")
                                                .font(.caption2)
                                                .fontWeight(.semibold)
                                            Text(vm.currencyString(firstPoint.balance))
                                                .font(.caption2)
                                        }
                                        .padding(4)
                                        .background(Color(.systemGray6))
                                        .cornerRadius(4)
                                    }
                                    .padding(8)
                                }
                                Spacer()
                            }
                            
                            // Ending point - tap to set target balance
                            if let lastPoint = vm.breakdown.last {
                                Button(action: {
                                    vm.selectedDataPoint = vm.breakdown.count - 1
                                    targetBalance = String(Int(lastPoint.balance))
                                }) {
                                    VStack {
                                        Circle()
                                            .fill(vm.selectedDataPoint == vm.breakdown.count - 1 ? Color.red : Color.green)
                                            .frame(width: 12, height: 12)
                                        
                                        VStack(spacing: 2) {
                                            Text("Final")
                                                .font(.caption2)
                                                .fontWeight(.semibold)
                                            Text(vm.currencyString(lastPoint.balance))
                                                .font(.caption2)
                                        }
                                        .padding(4)
                                        .background(Color(.systemGray6))
                                        .cornerRadius(4)
                                    }
                                    .padding(8)
                                }
                            }
                        }
                        Spacer()
                    }
                    .frame(height: 240)
                }
                
                // Selected point actions
                if let selectedIndex = vm.selectedDataPoint {
                    let dataPoint = vm.breakdown[selectedIndex]
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Divider()
                        
                        if selectedIndex == 0 {
                            // First point - change initial investment
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Modify Starting Balance")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                
                                HStack {
                                    Text("Enter new starting amount:")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                
                                HStack {
                                    Text(vm.currency.rawValue)
                                        .foregroundColor(.secondary)
                                    TextField("Amount", text: Binding(
                                        get: { vm.initialInvestment },
                                        set: { newValue in
                                            vm.initialInvestment = newValue
                                        }
                                    ))
                                    .keyboardType(.decimalPad)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                }
                                
                                Button(action: {
                                    vm.calculate()
                                    vm.selectedDataPoint = nil
                                }) {
                                    HStack {
                                        Spacer()
                                        Text("Apply")
                                            .foregroundColor(.white)
                                        Spacer()
                                    }
                                    .padding(.vertical, 8)
                                    .background(Color.blue)
                                    .cornerRadius(6)
                                }
                            }
                        } else if selectedIndex == vm.breakdown.count - 1 {
                            // Last point - calculate required interest rate
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Calculate Required Interest Rate")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                
                                HStack {
                                    Text("Target final balance:")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                
                                HStack {
                                    Text(vm.currency.rawValue)
                                        .foregroundColor(.secondary)
                                    TextField("Target", text: $targetBalance)
                                        .keyboardType(.decimalPad)
                                        .textFieldStyle(RoundedBorderTextFieldStyle())
                                }
                                
                                HStack {
                                    Text("Current interest rate:")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text(vm.interestRate + "%")
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.orange)
                                }
                                
                                Button(action: {
                                    if let target = Double(targetBalance) {
                                        vm.setInterestRateFromFinalBalance(targetBalance: target)
                                    }
                                    vm.selectedDataPoint = nil
                                }) {
                                    HStack {
                                        Spacer()
                                        Text("Update Interest Rate")
                                            .foregroundColor(.white)
                                        Spacer()
                                    }
                                    .padding(.vertical, 8)
                                    .background(Color.orange)
                                    .cornerRadius(6)
                                }
                                
                                Text("The interest rate has been adjusted to reach your target balance.")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .italic()
                            }
                        } else {
                            // Middle point - show info
                            HStack {
                                VStack(alignment: .leading) {
                                    Text("Year \(dataPoint.year)")
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                    Text(vm.currencyString(dataPoint.balance))
                                        .font(.title3)
                                        .foregroundColor(.green)
                                }
                                Spacer()
                                VStack(alignment: .trailing) {
                                    Text("Interest this year")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text(vm.currencyString(dataPoint.interest))
                                        .font(.headline)
                                        .foregroundColor(.orange)
                                }
                            }
                        }
                        
                        Button(action: { vm.selectedDataPoint = nil }) {
                            Text("Close")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.top, 8)
                }
            } else {
                Text("Click 'Calculate' to generate the chart")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(height: 200)
                    .frame(maxWidth: .infinity, alignment: .center)
            }

            HStack(spacing: 16) {
                Label("Balance", systemImage: "circle.fill")
                    .font(.caption)
                    .foregroundColor(.green)
                Label("Deposits", systemImage: "circle.fill")
                    .font(.caption)
                    .foregroundColor(.blue)
            }
        }
    }
}

struct BreakdownBlock: View {
    @ObservedObject var vm: CompoundInterestViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Yearly breakdown")
                .font(.headline)
                .foregroundColor(.orange)
                .padding(.horizontal, 12)
            TableHeader()
                .padding(.horizontal, 12)
            ForEach(vm.breakdown) { row in
                HStack {
                    Text("\(row.year)")
                        .frame(width: 40, alignment: .trailing)
                    Text(vm.currencyString(row.interest))
                        .frame(width: 100, alignment: .trailing)
                    Text(vm.currencyString(row.accruedInterest))
                        .frame(width: 120, alignment: .trailing)
                    Text(vm.currencyString(row.balance))
                        .frame(width: 120, alignment: .trailing)
                }
                .font(.system(size: 15, weight: .medium, design: .monospaced))
                .padding(.vertical, 4)
                .padding(.horizontal, 12)
                .background(row.year % 2 == 0 ? Color(.systemGray6) : Color.clear)
            }
        }
        .padding(.top, 8)
    }
}

struct TableHeader: View {
    var body: some View {
        HStack {
            Text("Year")
                .frame(width: 40, alignment: .trailing)
            Text("Interest")
                .frame(width: 100, alignment: .trailing)
            Text("Accrued Interest")
                .frame(width: 120, alignment: .trailing)
            Text("Balance")
                .frame(width: 120, alignment: .trailing)
        }
        .font(.system(size: 15, weight: .bold, design: .monospaced))
        .foregroundColor(.secondary)
        .padding(.vertical, 2)
    }
}

// MARK: - App Entry

