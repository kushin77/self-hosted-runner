#!/bin/bash
#
# visualize-dependencies.sh - Visualize dependency graph and usage patterns
#
# Generates:
# - Text-based dependency tree
# - Graphviz DOT format
# - HTML interactive visualization
# - Usage statistics
#

set -euo pipefail

METADATA_DIR="metadata"
OUTPUT_DIR="dependency-reports"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

mkdir -p "$OUTPUT_DIR"

echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║ DEPENDENCY VISUALIZATION${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# ============================================================================
# 1. Text-based dependency tree
# ============================================================================
echo -e "${BLUE}Generating text-based dependency tree...${NC}"
cat > "$OUTPUT_DIR/dependency-tree.txt" << 'EOF'
DEPENDENCY TREE
===============

Legend:
  → : depends on
  ◇ : critical item
  ○ : normal item

EOF

jq -r '.dependencies[] | "\(.from) → \(.to) [\(.type)]"' "$METADATA_DIR/dependencies.json" | \
    sort | while read -r line; do
    from=$(echo "$line" | cut -d' ' -f1)
    to=$(echo "$line" | cut -d' ' -f3)
    type=$(echo "$line" | cut -d'[' -f2 | cut -d']' -f1)
    
    # Check if from is critical
    is_critical=$(jq --arg id "$from" '.workflows[]? | select(.id == $id) | .risk_level' "$METADATA_DIR/items.json" 2>/dev/null || echo "")
    if [[ "$is_critical" == '"CRITICAL"' ]]; then
        marker="◇"
    else
        marker="○"
    fi
    
    printf "  %s %s → %s (%s)\n" "$marker" "$from" "$to" "$type"
done >> "$OUTPUT_DIR/dependency-tree.txt"

echo -e "${GREEN}✓${NC} Saved to: $OUTPUT_DIR/dependency-tree.txt"
echo ""

# ============================================================================
# 2. Graphviz DOT format
# ============================================================================
echo -e "${BLUE}Generating Graphviz visualization...${NC}"
cat > "$OUTPUT_DIR/dependencies.dot" << 'EOF'
digraph Dependencies {
    rankdir=LR;
    node [shape=box, style=rounded, fontname="Arial"];
    edge [fontname="Arial"];
    
EOF

# Add nodes with colors based on risk level
jq -r '.workflows[]? | .id' "$METADATA_DIR/items.json" 2>/dev/null | while read -r id; do
    risk=$(jq --arg id "$id" '.workflows[]? | select(.id == $id) | .risk_level' "$METADATA_DIR/items.json" 2>/dev/null)
    
    case "$risk" in
        '"CRITICAL"') color="red" ;;
        '"HIGH"') color="orange" ;;
        '"MEDIUM"') color="yellow" ;;
        '"LOW"') color="green" ;;
        *) color="lightblue" ;;
    esac
    
    echo "    \"$id\" [fillcolor=$color, style=\"filled,rounded\"];"
done >> "$OUTPUT_DIR/dependencies.dot"

# Add edges
jq -r '.dependencies[] | "\"\(.from)\" -> \"\(.to)\" [label=\"\(.type)\"];"' "$METADATA_DIR/dependencies.json" 2>/dev/null >> "$OUTPUT_DIR/dependencies.dot"

cat >> "$OUTPUT_DIR/dependencies.dot" << 'EOF'
}
EOF

echo -e "${GREEN}✓${NC} Saved to: $OUTPUT_DIR/dependencies.dot"

# Try to generate SVG if graphviz is installed
if command -v dot &> /dev/null; then
    dot -Tsvg "$OUTPUT_DIR/dependencies.dot" -o "$OUTPUT_DIR/dependencies.svg"
    echo -e "${GREEN}✓${NC} Generated SVG: $OUTPUT_DIR/dependencies.svg"
fi
echo ""

# ============================================================================
# 3. Dependency Statistics
# ============================================================================
echo -e "${BLUE}Generating dependency statistics...${NC}"

cat > "$OUTPUT_DIR/dependency-stats.txt" << 'EOF'
DEPENDENCY STATISTICS
=====================

EOF

# Most depended-on items
echo "Top 10 Most Depended On:" >> "$OUTPUT_DIR/dependency-stats.txt"
jq -r '.dependencies[] | .to' "$METADATA_DIR/dependencies.json" 2>/dev/null | \
    sort | uniq -c | sort -rn | head -10 | \
    awk '{printf "  %s: %d dependencies\n", $2, $1}' >> "$OUTPUT_DIR/dependency-stats.txt"
echo "" >> "$OUTPUT_DIR/dependency-stats.txt"

# Items with most dependencies
echo "Top 10 Items with Most Dependencies:" >> "$OUTPUT_DIR/dependency-stats.txt"
jq -r '.dependencies[] | .from' "$METADATA_DIR/dependencies.json" 2>/dev/null | \
    sort | uniq -c | sort -rn | head -10 | \
    awk '{printf "  %s depends on: %d items\n", $2, $1}' >> "$OUTPUT_DIR/dependency-stats.txt"
echo "" >> "$OUTPUT_DIR/dependency-stats.txt"

# Dependency types
echo "Dependency Type Distribution:" >> "$OUTPUT_DIR/dependency-stats.txt"
jq -r '.dependencies[] | .type' "$METADATA_DIR/dependencies.json" 2>/dev/null | \
    sort | uniq -c | \
    awk '{printf "  %s: %d\n", $2, $1}' >> "$OUTPUT_DIR/dependency-stats.txt"

echo -e "${GREEN}✓${NC} Saved to: $OUTPUT_DIR/dependency-stats.txt"
echo ""

# ============================================================================
# 4. HTML Interactive Visualization
# ============================================================================
echo -e "${BLUE}Generating HTML visualization...${NC}"
cat > "$OUTPUT_DIR/dependencies.html" << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>Dependency Visualization</title>
    <script src="https://d3js.org/d3.v7.min.js"></script>
    <style>
        body {
            font-family: Arial, sans-serif;
            margin: 0;
            padding: 20px;
            background-color: #f5f5f5;
        }
        #graph {
            background-color: white;
            border: 1px solid #ccc;
            border-radius: 4px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        }
        .node {
            stroke: #fff;
            stroke-width: 1.5px;
            cursor: pointer;
        }
        .node:hover {
            stroke: #000;
            stroke-width: 2px;
        }
        .link {
            stroke: #999;
            stroke-opacity: 0.6;
        }
        .critical { fill: #ff6b6b; }
        .high { fill: #ffa94d; }
        .medium { fill: #ffd93d; }
        .low { fill: #6bcf7f; }
        
        #info {
            margin-top: 20px;
            padding: 15px;
            background-color: white;
            border: 1px solid #ccc;
            border-radius: 4px;
        }
        h1, h2 {
            color: #333;
        }
    </style>
</head>
<body>
    <h1>Dependency Visualization</h1>
    <div id="graph"></div>
    <div id="info">
        <h2>Instructions</h2>
        <p>Hover over nodes to highlight. Click to expand/collapse dependencies.</p>
        <p><strong>Color Legend:</strong>
            <span style="color: #ff6b6b;">● Critical</span> |
            <span style="color: #ffa94d;">● High</span> |
            <span style="color: #ffd93d;">● Medium</span> |
            <span style="color: #6bcf7f;">● Low</span>
        </p>
    </div>
    
    <script>
        // Placeholder for D3 visualization
        // In production, this would be filled with actual data
        document.getElementById('info').innerHTML += '<p><em>Note: Load dependencies.json data for interactive visualization</em></p>';
    </script>
</body>
</html>
EOF

echo -e "${GREEN}✓${NC} Saved to: $OUTPUT_DIR/dependencies.html"
echo ""

# ============================================================================
# 5. Risk Analysis
# ============================================================================
echo -e "${BLUE}Analyzing risk dependencies...${NC}"
cat > "$OUTPUT_DIR/risk-analysis.txt" << 'EOF'
RISK DEPENDENCY ANALYSIS
========================

Critical Items Depending on:
EOF

jq -r '.workflows[]? | select(.risk_level == "CRITICAL") | .id' "$METADATA_DIR/items.json" 2>/dev/null | \
    while read -r critical_id; do
        echo "" >> "$OUTPUT_DIR/risk-analysis.txt"
        echo "  [$critical_id]" >> "$OUTPUT_DIR/risk-analysis.txt"
        jq -r --arg id "$critical_id" '.dependencies[] | select(.from == $id) | "    → \(.to) (\(.type))"' "$METADATA_DIR/dependencies.json" 2>/dev/null >> "$OUTPUT_DIR/risk-analysis.txt"
    done

echo "" >> "$OUTPUT_DIR/risk-analysis.txt"
echo "Items Depended On by Critical:" >> "$OUTPUT_DIR/risk-analysis.txt"

jq -r '.dependencies[] | select(.from | [length] > [0]) | .to' "$METADATA_DIR/dependencies.json" 2>/dev/null | \
    sort | uniq | while read -r dep_id; do
        count=$(jq --arg id "$dep_id" '[.dependencies[] | select(.to == $id) | .from] | map(select(. != null)) | length' "$METADATA_DIR/dependencies.json" 2>/dev/null)
        echo "  $dep_id (required by $count items)" >> "$OUTPUT_DIR/risk-analysis.txt"
    done

echo -e "${GREEN}✓${NC} Saved to: $OUTPUT_DIR/risk-analysis.txt"
echo ""

# ============================================================================
# Summary
# ============================================================================
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}✓ Visualization complete!${NC}"
echo ""
echo "Generated reports:"
ls -1 "$OUTPUT_DIR"/ | sed 's/^/  - /'
echo ""
echo "View HTML visualization in a browser:"
echo "  open $OUTPUT_DIR/dependencies.html"
