const { createClient } = require('@supabase/supabase-js');
const supabase = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY);

// Hàm lấy danh sách đánh giá
const getPublicReviews = async (req, res) => {
    try {
        const { data, error } = await supabase
            .from('app_reviews')
            .select(`
                id, rating, comment, created_at,
                users ( full_name, avatar_url, username )
            `)
            .order('created_at', { ascending: false })
            .limit(50);

        if (error) {
            throw error;
        }

        return res.status(200).json({
            success: true,
            data: data
        });

    } catch (err) {
        console.error("Lỗi lấy danh sách review:", err.message);
        return res.status(500).json({
            success: false,
            message: "Lỗi server khi tải đánh giá"
        });
    }
};

module.exports = {
    getPublicReviews
};