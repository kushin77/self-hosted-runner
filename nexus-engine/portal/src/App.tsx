import React from 'react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { ThemeProvider, createTheme, CssBaseline, Container, AppBar, Toolbar, Typography, Box, Tabs, Tab } from '@mui/material'
import Dashboard from './components/Dashboard'
import KafkaMetrics from './components/KafkaMetrics'
import NormalizerJobs from './components/NormalizerJobs'
import AuditLogViewer from './components/AuditLogViewer'

const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      refetchInterval: 5000,
      retry: 1,
    }
  }
})

const theme = createTheme({
  palette: {
    mode: 'light',
    primary: {
      main: '#1976d2',
    },
    secondary: {
      main: '#dc004e',
    },
    background: {
      default: '#f5f5f5',
    }
  },
  typography: {
    fontFamily: '"Roboto", "Helvetica", "Arial", sans-serif',
    h5: {
      fontWeight: 600,
    }
  }
})

interface TabPanelProps {
  children?: React.ReactNode;
  index: number;
  value: number;
}

function TabPanel(props: TabPanelProps) {
  const { children, value, index, ...other } = props;
  return (
    <div
      role="tabpanel"
      hidden={value !== index}
      id={`tabpanel-${index}`}
      aria-labelledby={`tab-${index}`}
      {...other}
    >
      {value === index && <Box sx={{ p: 3 }}>{children}</Box>}
    </div>
  );
}

export default function App() {
  const [tabIndex, setTabIndex] = React.useState(0);

  return (
    <QueryClientProvider client={queryClient}>
      <ThemeProvider theme={theme}>
        <CssBaseline />
        <AppBar position="static">
          <Toolbar>
            <Typography variant="h6" component="div" sx={{ flexGrow: 1 }}>
              ⚡ NEXUS Ops Portal
            </Typography>
            <Typography variant="caption" sx={{ pr: 2 }}>
              Real-time Discovery Pipeline Observability
            </Typography>
          </Toolbar>
        </AppBar>
        
        <Container maxWidth="lg" sx={{ py: 4 }}>
          <Tabs
            value={tabIndex}
            onChange={(e, newValue) => setTabIndex(newValue)}
            aria-label="portal tabs"
            sx={{ borderBottom: 1, borderColor: 'divider', mb: 3 }}
          >
            <Tab label="Dashboard" id="tab-0" aria-controls="tabpanel-0" />
            <Tab label="Kafka Metrics" id="tab-1" aria-controls="tabpanel-1" />
            <Tab label="Normalizer Jobs" id="tab-2" aria-controls="tabpanel-2" />
            <Tab label="Audit Logs" id="tab-3" aria-controls="tabpanel-3" />
          </Tabs>

          <TabPanel value={tabIndex} index={0}>
            <Dashboard />
          </TabPanel>
          <TabPanel value={tabIndex} index={1}>
            <KafkaMetrics />
          </TabPanel>
          <TabPanel value={tabIndex} index={2}>
            <NormalizerJobs />
          </TabPanel>
          <TabPanel value={tabIndex} index={3}>
            <AuditLogViewer />
          </TabPanel>
        </Container>
      </ThemeProvider>
    </QueryClientProvider>
  )
}
