import { Routes, Route, Navigate } from 'react-router-dom';
import CheckoutPage from './CheckoutPage';
import SuccessPage from './SuccessPage';

export default function App() {
  return (
    <Routes>
      <Route path="/" element={<Navigate to="/checkout" replace />} />
      <Route path="/checkout" element={<CheckoutPage />} />
      <Route path="/success" element={<SuccessPage />} />
    </Routes>
  );
}
