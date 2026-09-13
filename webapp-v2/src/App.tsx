import { useEffect } from 'react'
import { BrowserRouter, Route, Routes, useLocation } from 'react-router-dom'
import { WagmiProvider } from 'wagmi'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { config } from '@/config/wagmi'
import { AuthProvider } from '@/contexts/AuthContext'
import { useAuth } from '@/hooks/useAuth'
import { captureReferralCode, connectPendingReferral } from '@/lib/referrals'

import { OddsShiftPage } from '@/pages/OddsShiftPage'
const queryClient = new QueryClient()

function ReferralTracker() {
  const location = useLocation()
  const { isAuthenticated } = useAuth()

  useEffect(() => {
    captureReferralCode(location.search)
  }, [location.search])

  useEffect(() => {
    if (isAuthenticated) void connectPendingReferral()
  }, [isAuthenticated])

  return null
}

function App() {
  return (
    <WagmiProvider config={config}>
      <QueryClientProvider client={queryClient}>
        <AuthProvider>
          <BrowserRouter>
            <ReferralTracker />
            <Routes>
              <Route path="/oddsshift/:contractAddress" element={<OddsShiftPage />} />
            </Routes>
          </BrowserRouter>
        </AuthProvider>
      </QueryClientProvider>
    </WagmiProvider>
  )
}

export default App
