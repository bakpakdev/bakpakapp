const { getSupabaseAdmin } = require('../lib/supabaseAdmin');

async function protectSupabase(req, res, next) {
  try {
    const header = req.headers.authorization;
    if (!header || !header.startsWith('Bearer ')) {
      return res.status(401).json({ message: 'Not authorized, no token' });
    }

    const token = header.split(' ')[1];
    const supabase = getSupabaseAdmin();
    const { data, error } = await supabase.auth.getUser(token);

    if (error || !data?.user) {
      return res.status(401).json({ message: 'Not authorized, invalid token' });
    }

    req.user = {
      id: data.user.id.toLowerCase(),
      email: data.user.email,
    };
    next();
  } catch (err) {
    console.error('Supabase auth error:', err);
    res.status(500).json({ message: 'Server error', error: err.message });
  }
}

module.exports = { protectSupabase };
