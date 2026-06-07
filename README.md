# Let's talk about congestion pricing

This repository hosts ongoing academic work led by staff and students investigating the **design, data, and potential impacts of Auckland’s upcoming congestion pricing (CP) scheme**. The project aims to connect **geospatial analytics, traffic datasets, and behavioural modelling** to understand the spatial and social implications of road pricing in the Auckland region.

---

## 🔍 Overview

Congestion pricing is being considered as part of Auckland’s broader transport demand management strategy. Our work focuses on:

- Estimating traffic volume and congestion using open-source data  
- Analysing commuter flow patterns across different transport modes  
- Reviewing global experiences (London, Stockholm, Singapore, etc.) to inform Auckland’s design  
- Assessing the potential spatial spillover and equity impacts  

---

## 🗂️ Data Sources

### **1. TomTom Traffic Statistics**
We use **TomTom Traffic Stats – Area Analysis** to estimate congestion levels and travel speeds across Auckland’s urban road network.

- Aggregated at the **road segment level**
- Includes **travel time, delay index, and speed variation** by hour and day  
- Time range: 15–21 August 2024  
- Processed and analysed using R and Python (see `scripts/traffic_analysis/`)

### **2. Commuter Origin–Destination (OD) Data**
**Source:** Stats NZ [Census 2023 Commuter Dataset](https://datafinder.stats.govt.nz/data/category/census/2023/commuter-dataset/)  

- Provides **home-to-work OD flows** across SA2/SA3 regions  
- Used to map potential CP zone influence areas and assess alternative route choices  
- Integrated using `sf` and `sfnetworks` packages  


### **3. Agent-based modelling**

- Modelling Auckland transport using 2023 Census data  
- Developing inputs for an agent-based model of Auckland’s transport system  
- In collaboration with the University of Glasgow (TBC)


---

## 🧮 Current Work

| Theme | Description | Data | Tools |
|-------|--------------|------|-------|
| Road Volume Estimation | Traffic intensity across key corridors | TomTom | Python, R (`sf`, `tmap`) |
| Commuter Network Analysis | OD linkages and flow density | Stats NZ OD | R (`sfnetworks`, `igraph`) |
| Spatial Impact Modelling | CP zone extent and spillover | Combined | GAMA, R |
| Literature Review | Global CP & LEZ case synthesis | Scopus, Google Scholar | Zotero |

---

## 🧑‍💻 Team

This repository is maintained by a research group of academics and students from the **University of Auckland**, specialising in **GIScience, Urban Analytics, and Environmental Health**.

Additional collaborator:

- **Saeid Adli** – *Spatial Economics*  
  Contribution: modelling Auckland transport using 2023 Census data for an agent-based model.  
  📧 [saeid.adli@spatialeconomics.co.nz](mailto:saeid.adli@spatialeconomics.co.nz)


---

## 📄 Outputs

- Comparative database of global CP and LEZ schemes  
- Preliminary spatial visualisations for Auckland’s potential CP zones  
- Working paper (under preparation): *“Congestion Pricing and Spatial Spillovers: Lessons for Auckland”*  

---

## 📬 Contact

For collaboration or data inquiries, please contact:  
**Dr Hyesop Shin** – *Lecturer in GIScience, University of Auckland*  
📧 [hyesop.shin@auckland.ac.nz](mailto:hyesop.shin@auckland.ac.nz)

**Saeid Adli** – *Spatial Economics*  
📧 [saeid.adli@spatialeconomics.co.nz](mailto:saeid.adli@spatialeconomics.co.nz)
