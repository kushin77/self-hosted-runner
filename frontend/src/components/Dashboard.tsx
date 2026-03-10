// Re-export the production Dashboard from Dashboard_v2.tsx
export { default } from './Dashboard_v2';
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        ) : (
          <p className="text-gray-500">{loading ? 'Loading credentials...' : 'No credentials found'}</p>
        )}
      </div>

      {/* Audit Trail */}
      <div className="bg-gray-800 rounded-lg p-6">
        <h2 className="text-xl font-bold mb-4">📋 Audit Trail (Last 50 entries)</h2>
        {auditTrail.length > 0 ? (
          <div className="space-y-2 max-h-96 overflow-y-auto">
            {auditTrail.slice(-10).reverse().map((entry, idx) => (
              <div key={idx} className="bg-gray-900 p-3 rounded text-xs font-mono text-gray-400">
                <div className="flex justify-between">
                  <span className="text-gray-300">{entry.method}</span>
                  <span>{entry.path}</span>
                  <span className="text-gray-500">{new Date(entry.timestamp).toLocaleTimeString()}</span>
                </div>
              </div>
            ))}
          </div>
        ) : (
          <p className="text-gray-500">{loading ? 'Loading audit trail...' : 'No audit entries found'}</p>
        )}
      </div>

      {/* Footer */}
      <div className="mt-8 border-t border-gray-700 pt-4 text-center text-gray-500 text-xs">
        <p>
          NexusShield Portal MVP v1.0.0-alpha | Last updated: {new Date().toLocaleString()}
        </p>
      </div>
    </div>
  );
};

export default Dashboard;
