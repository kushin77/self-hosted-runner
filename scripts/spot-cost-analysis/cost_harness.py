#!/usr/bin/env python3
"""
AWS EC2 Spot Instance Cost Analysis Harness

Analyzes pricing for spot vs on-demand instances across regions and instance types.
Fetches pricing data from AWS Pricing API and generates cost comparison reports.
"""

import json
import argparse
import logging
from typing import Dict, List, Tuple, Optional
from datetime import datetime
import sys

# Mock pricing data for demonstration (in production, integrate with AWS Pricing API)
MOCK_PRICING_DATA = {
    "us-east-1": {
        "on-demand": {
            "t2.small": 0.0247,
            "t2.medium": 0.0494,
            "t3.small": 0.0208,
            "t3.medium": 0.0416,
            "m5.large": 0.096,
            "c5.large": 0.085,
        },
        "spot": {
            "t2.small": 0.0074,
            "t2.medium": 0.0148,
            "t3.small": 0.0062,
            "t3.medium": 0.0125,
            "m5.large": 0.0288,
            "c5.large": 0.0255,
        }
    },
    "us-west-2": {
        "on-demand": {
            "t2.small": 0.0247,
            "t2.medium": 0.0494,
            "t3.small": 0.0208,
            "t3.medium": 0.0416,
            "m5.large": 0.096,
            "c5.large": 0.085,
        },
        "spot": {
            "t2.small": 0.0070,
            "t2.medium": 0.0140,
            "t3.small": 0.0058,
            "t3.medium": 0.0115,
            "m5.large": 0.0270,
            "c5.large": 0.0242,
        }
    },
    "eu-west-1": {
        "on-demand": {
            "t2.small": 0.0271,
            "t2.medium": 0.0542,
            "t3.small": 0.0228,
            "t3.medium": 0.0456,
            "m5.large": 0.1055,
            "c5.large": 0.0934,
        },
        "spot": {
            "t2.small": 0.0081,
            "t2.medium": 0.0162,
            "t3.small": 0.0068,
            "t3.medium": 0.0136,
            "m5.large": 0.0316,
            "c5.large": 0.0280,
        }
    }
}

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


class SpotCostAnalyzer:
    """Analyzes spot vs on-demand instance costs across regions."""
    
    def __init__(self):
        self.pricing_data = MOCK_PRICING_DATA
        
    def get_instance_pricing(self, instance_type: str, region: str, price_type: str = "spot") -> Optional[float]:
        """
        Retrieve pricing for an instance type in a given region.
        
        Args:
            instance_type: EC2 instance type (e.g., 't2.small')
            region: AWS region (e.g., 'us-east-1')
            price_type: 'spot' or 'on-demand'
            
        Returns:
            Price in USD per hour, or None if not found
        """
        try:
            return self.pricing_data.get(region, {}).get(price_type, {}).get(instance_type)
        except (KeyError, TypeError):
            return None
    
    def calculate_savings(self, on_demand_price: float, spot_price: float) -> float:
        """Calculate savings percentage."""
        if on_demand_price == 0:
            return 0.0
        return ((on_demand_price - spot_price) / on_demand_price) * 100
    
    def analyze_instance(self, instance_type: str, regions: List[str]) -> Dict:
        """Analyze an instance type across multiple regions."""
        analysis = {
            "type": instance_type,
            "regions": {},
            "average_on_demand": 0.0,
            "average_spot_price": 0.0,
            "average_savings_pct": 0.0,
        }
        
        od_prices = []
        spot_prices = []
        
        for region in regions:
            od_price = self.get_instance_pricing(instance_type, region, "on-demand")
            spot_price = self.get_instance_pricing(instance_type, region, "spot")
            
            if od_price is None or spot_price is None:
                logger.warning(f"Pricing not found for {instance_type} in {region}")
                continue
            
            savings = self.calculate_savings(od_price, spot_price)
            
            analysis["regions"][region] = {
                "on_demand_price": od_price,
                "spot_price": spot_price,
                "savings_pct": savings,
                "hourly_savings": od_price - spot_price,
                "daily_savings": (od_price - spot_price) * 24,
                "monthly_savings": (od_price - spot_price) * 24 * 30,
            }
            
            od_prices.append(od_price)
            spot_prices.append(spot_price)
        
        if od_prices and spot_prices:
            analysis["average_on_demand"] = sum(od_prices) / len(od_prices)
            analysis["average_spot_price"] = sum(spot_prices) / len(spot_prices)
            analysis["average_savings_pct"] = self.calculate_savings(
                analysis["average_on_demand"],
                analysis["average_spot_price"]
            )
        
        return analysis
    
    def analyze_batch(self, instance_types: List[str], regions: List[str]) -> Dict:
        """Analyze multiple instance types across regions."""
        results = {
            "timestamp": datetime.utcnow().isoformat() + "Z",
            "regions": regions,
            "instance_types": instance_types,
            "instances": [],
            "summary": {
                "total_instances_analyzed": len(instance_types),
                "avg_savings_pct": 0.0,
                "cheapest_instance_type": None,
                "most_expensive_instance_type": None,
            }
        }
        
        savings_pcts = []
        cheapest_spot = None
        most_expensive_spot = None
        
        for itype in instance_types:
            analysis = self.analyze_instance(itype, regions)
            results["instances"].append(analysis)
            
            if analysis.get("average_savings_pct"):
                savings_pcts.append(analysis["average_savings_pct"])
            
            # Track cheapest/most expensive
            avg_spot = analysis.get("average_spot_price", 0)
            if cheapest_spot is None or avg_spot < cheapest_spot:
                cheapest_spot = avg_spot
                results["summary"]["cheapest_instance_type"] = itype
            
            if most_expensive_spot is None or avg_spot > most_expensive_spot:
                most_expensive_spot = avg_spot
                results["summary"]["most_expensive_instance_type"] = itype
        
        if savings_pcts:
            results["summary"]["avg_savings_pct"] = sum(savings_pcts) / len(savings_pcts)
        
        return results
    
    def generate_report(self, analysis: Dict) -> str:
        """Generate a formatted report from analysis results."""
        report = []
        report.append("=" * 80)
        report.append("AWS EC2 Spot vs On-Demand Cost Analysis Report")
        report.append("=" * 80)
        report.append(f"Generated: {analysis['timestamp']}")
        report.append(f"Regions: {', '.join(analysis['regions'])}")
        report.append("")
        
        report.append("INSTANCE TYPE ANALYSIS")
        report.append("-" * 80)
        report.append(f"{'Instance Type':<15} {'On-Demand':<12} {'Spot Avg':<12} {'Savings %':<10} {'Monthly Savings':<15}")
        report.append("-" * 80)
        
        for instance in analysis["instances"]:
            itype = instance["type"]
            od_price = instance["average_on_demand"]
            spot_price = instance["average_spot_price"]
            savings = instance["average_savings_pct"]
            monthly_savings = (od_price - spot_price) * 24 * 30
            
            report.append(
                f"{itype:<15} ${od_price:<11.4f} ${spot_price:<11.4f} {savings:<9.1f}% ${monthly_savings:<14.2f}"
            )
        
        report.append("")
        report.append("SUMMARY")
        report.append("-" * 80)
        summary = analysis["summary"]
        report.append(f"Average Savings: {summary['avg_savings_pct']:.1f}%")
        report.append(f"Cheapest Instance Type: {summary['cheapest_instance_type']}")
        report.append(f"Most Expensive Instance Type: {summary['most_expensive_instance_type']}")
        report.append("")
        
        report.append("RECOMMENDATIONS")
        report.append("-" * 80)
        report.append("1. Use Spot instances for non-critical or fault-tolerant workloads")
        report.append("2. Combine Spot with On-Demand (20-30% mix) for production stability")
        report.append(f"3. Prioritize {summary['cheapest_instance_type']} for best cost savings")
        report.append("4. Implement lifecycle hooks to gracefully handle spot interruptions")
        report.append("5. Monitor interruption rates and adjust allocation strategy if needed")
        report.append("")
        
        return "\n".join(report)


def main():
    parser = argparse.ArgumentParser(
        description="Analyze AWS EC2 Spot Instance Costs"
    )
    parser.add_argument(
        "--instance-types",
        type=str,
        default="t2.small,t2.medium,t3.small,t3.medium",
        help="Comma-separated list of instance types to analyze"
    )
    parser.add_argument(
        "--regions",
        type=str,
        default="us-east-1,us-west-2",
        help="Comma-separated list of AWS regions to analyze"
    )
    parser.add_argument(
        "--output-format",
        type=str,
        choices=["json", "text", "both"],
        default="text",
        help="Output format (json, text, or both)"
    )
    parser.add_argument(
        "--output-file",
        type=str,
        help="Output file path (omit for stdout)"
    )
    
    args = parser.parse_args()
    
    instance_types = [t.strip() for t in args.instance_types.split(",")]
    regions = [r.strip() for r in args.regions.split(",")]
    
    logger.info(f"Analyzing {len(instance_types)} instance types across {len(regions)} regions")
    
    analyzer = SpotCostAnalyzer()
    analysis = analyzer.analyze_batch(instance_types, regions)
    
    # Generate text report
    text_report = analyzer.generate_report(analysis)
    
    # Output results
    if args.output_format in ["text", "both"]:
        print(text_report)
        
        if args.output_file:
            with open(args.output_file.replace(".json", ".txt"), "w") as f:
                f.write(text_report)
                logger.info(f"Text report saved to {args.output_file.replace('.json', '.txt')}")
    
    if args.output_format in ["json", "both"]:
        json_output = json.dumps(analysis, indent=2)
        
        if args.output_file:
            with open(args.output_file, "w") as f:
                f.write(json_output)
                logger.info(f"JSON output saved to {args.output_file}")
        else:
            print(json_output)
    
    return 0


if __name__ == "__main__":
    sys.exit(main())
