# Auckland 2023 MATSim Population Plans (10% Sample)

`output/plans_10pct.xml.gz` is a 10% representative synthetic population activity plan dataset for the Auckland region, formatted according to the MATSim `population_v6.dtd` XML schema.

---

## 1. Overview & Dataset Statistics

| Metric | Full Population (100%) | Model Plans (10% Sample) | Calibration Sample (1%) |
|:---|:---:|:---:|:---:|
| **File Name** | `output/plans_100pct.xml.gz` | `output/plans_10pct.xml.gz` | `output/plans_1pct.xml.gz` |
| **Gzip File Size** | ~1.4 GB | **~140 MB** | ~15 MB |
| **Number of Agents** | 1,600,065 persons | **~160,000 persons** | ~16,000 persons |
| **Household Count** | 539,133 households | **~54,000 households** | ~5,400 households |
| **Total Weekday Trips** | 5,940,000 trips | **~594,000 trips** | ~59,400 trips |
| **Coordinate System** | EPSG:2193 (NZTM2000) | **EPSG:2193 (NZTM2000)** | EPSG:2193 (NZTM2000) |
| **Simulation Scale (`flowCapacityFactor`)** | `1.00` | **`0.10`** | `0.01` |

---

## 2. How the Synthetic Population Was Generated

The population was generated using an end-to-end synthetic reconstruction pipeline:

1. **Demographic Synthesis (IPU)**:
   - Built using **Iterative Proportional Updating (IPU)** at the Statistical Area 1 (SA1) level across 10,476 zones.
   - Constrained simultaneously by Census 2023 household margins (household size, vehicle count) and person margins (age category, sex, labour force status).
   - Raked on the odds scale to match the 90.9% regional adult driving licence holding rate.

2. **Spatial Allocation (LINZ Address Points)**:
   - Rather than placing agents at arbitrary zone centroids, households are placed onto exact **LINZ property address coordinates** inside their assigned SA1.
   - Workplace locations are assigned at SA2 from the Census 2023 Journey-to-Work commuting matrix, with stated working-from-home workers explicitly retained at home.

3. **Daily Activity Chains (HTS Donor Days)**:
   - Each synthetic person inherits a complete 24-hour weekday activity schedule from a matched New Zealand **Household Travel Survey (HTS)** respondent (waves 17–21, averaging 3.71 trips/day).
   - Primary destinations (home, work, education) are anchored to owned locations. Discretionary destinations (shopping, leisure, personal) are drawn from spatial land-use attractors.
   - **Household Escorting**: Escort trips (school runs and pickups) are synthesized within the household so accompanying adults and children share exact departure times, origins, and destinations.

---

## 3. Subpopulations & Person Attributes

Every `<person>` contains attributes that define their demographic profile and choice set:

### Subpopulation Definitions

| Subpopulation (`subpopulation`) | Description | Regional Share | Available Modes | Reference Mode |
|:---|:---|:---:|:---|:---:|
| **`adult_car`** | Licensed adult with household vehicle access | 77.9% of trips | `car`, `ride`, `pt`, `bike`, `walk` | `car` |
| **`adult_lic_nocar`** | Licensed adult in a car-free household | 1.6% of trips | `ride`, `pt`, `bike`, `walk` | `walk` |
| **`adult_nolic`** | Unlicensed adult (16+ years) | 3.5% of trips | `ride`, `pt`, `bike`, `walk` | `walk` |
| **`child`** | Under 16 years of age | 17.0% of trips | `ride`, `pt`, `bike`, `walk` | `walk` |

### XML Attribute Schema

```xml
<person id="1">
  <attributes>
    <attribute name="household_id" class="java.lang.String">1</attribute>
    <attribute name="age" class="java.lang.String">40.0</attribute>
    <attribute name="sex" class="java.lang.String">female</attribute>
    <attribute name="income" class="java.lang.String">30_50k</attribute>
    <attribute name="labour_force" class="java.lang.String">employed_ft</attribute>
    <attribute name="occupation" class="java.lang.String">labourers</attribute>
    <attribute name="anzsic_industry" class="java.lang.String">Construction</attribute>
    <attribute name="hasLicense" class="java.lang.String">yes</attribute>
    <attribute name="carAvail" class="java.lang.String">always</attribute>
    <attribute name="subpopulation" class="java.lang.String">adult_car</attribute>
    <attribute name="SA12023_V1_00" class="java.lang.String">7001130</attribute>
    <attribute name="SA22023_V1_00" class="java.lang.String">111801</attribute>
    <attribute name="workplace_sa2" class="java.lang.String">111801</attribute>
    <attribute name="works_at_home" class="java.lang.String">True</attribute>
  </attributes>
  ...
</person>
```

---

## 4. Activity Plan Structure

Each person holds an executed activity schedule composed of alternating `<activity>` and `<leg>` tags:

```xml
<plan selected="yes">
  <!-- 1. Home Activity until Morning Departure -->
  <activity type="home" x="1757601.20" y="5920942.50" end_time="07:45:00"/>
  
  <!-- 2. Commute Trip to Work -->
  <leg mode="car"/>
  
  <!-- 3. Primary Work Activity -->
  <activity type="work" x="1754200.10" y="5918300.80" end_time="17:15:00"/>
  
  <!-- 4. Return Leg to Home -->
  <leg mode="car"/>
  
  <!-- 5. Evening Home Activity -->
  <activity type="home" x="1757601.20" y="5920942.50"/>
</plan>
```

### Activity Types:
- `home`: Residential base activities.
- `work`: Primary employment tours.
- `education`: University, secondary, and primary school attendance.
- `shop`: Grocery, retail, and shopping errands.
- `leisure`: Recreation, sports, social, and entertainment.
- `other` / `personal`: Healthcare, personal business, goods pick-up.

### Travel Modes:
- `car`: Driver trip on congested highway network.
- `ride`: Passenger trip (carpool, pickup, taxi, escort).
- `pt`: Scheduled transit (bus, train, ferry) on SwissRailRaptor router.
- `bike`: Bicycle trip on multimodal network (speed cap 14.4 km/h, `PassingQ`).
- `walk`: Teleported walking trip (1.2 m/s, beeline × 1.3) and transit access/egress.

---

## 5. Running with MATSim

When executing simulations with `plans_10pct.xml.gz`, the simulation network capacity **must** be scaled to match the 10% sample rate:

### Required MATSim Configuration (`config.xml`):

```xml
<module name="plans">
    <param name="inputPlansFile" value="plans_10pct.xml.gz" />
</module>

<module name="qsim">
    <!-- MUST match the 10% population sample rate -->
    <param name="flowCapacityFactor" value="0.10" />
    <param name="storageCapacityFactor" value="0.10" />
    <param name="mainMode" value="car,bike" />
    <param name="linkDynamics" value="PassingQ" />
    <param name="endTime" value="36:00:00" />
</module>
```

### Execution Command:

```powershell
java -Xmx16g -cp "tools/java/classes;tools/java/deps/*" org.matsim.run.RunSE0327 output/matsim/config_calibrated_base2023.xml output/matsim/pricing
```

---

## 6. Related Model Files

- **Master Configuration**: [`output/matsim/config_calibrated_base2023.xml`](file:///c:/Users/Saeid/OneDrive%20-%20Spatial%20Economics%20Ltd/Projects/SE0327_TransprotAppraisal/output/matsim/config_calibrated_base2023.xml)
- **Calibrated Parameters**: [`output/calibration/calibrated_parameters.json`](file:///c:/Users/Saeid/OneDrive%20-%20Spatial%20Economics%20Ltd/Projects/SE0327_TransprotAppraisal/output/calibration/calibrated_parameters.json)
- **Multimodal Elevated Network**: [`output/matsim/network_with_pt.xml.gz`](file:///c:/Users/Saeid/OneDrive%20-%20Spatial%20Economics%20Ltd/Projects/SE0327_TransprotAppraisal/output/matsim/network_with_pt.xml.gz)
- **Transit Schedule**: [`output/matsim/transitSchedule_pt.xml.gz`](file:///c:/Users/Saeid/OneDrive%20-%20Spatial%20Economics%20Ltd/Projects/SE0327_TransprotAppraisal/output/matsim/transitSchedule_pt.xml.gz)
- **Methodology & Calibration Report**: [`docs/model_report/model_report.pdf`](file:///c:/Users/Saeid/OneDrive%20-%20Spatial%20Economics%20Ltd/Projects/SE0327_TransprotAppraisal/docs/model_report/model_report.pdf)
